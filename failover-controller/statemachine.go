package main

import (
	"context"
	"fmt"
	"log"
	"time"
)

// Simplified state set. The original code had 8 states; we consolidate to 5
// that map cleanly to the failover lifecycle. The removed states (MONITORING,
// PREPARING, RESTORING) added ceremony without distinct behavior -- their
// logic is folded into the remaining states.
const (
	StateHealthy     = "HEALTHY"
	StateDegraded    = "DEGRADED"
	StateFailingOver = "FAILING_OVER"
	StateFailedOver  = "FAILED_OVER"
	StateRecovering  = "RECOVERING"
)

// Thresholds for health score evaluation.
const (
	// DegradeThreshold: primary score below this triggers transition to DEGRADED.
	DegradeThreshold = 0.5

	// FailoverThreshold: consecutive degraded checks required before failover.
	ConsecutiveDegradedChecksRequired = 3

	// RecoveryThreshold: primary score above this in FAILED_OVER starts recovery.
	RecoveryThreshold = 0.7

	// HealthScoreWindow is the lookback period for computing health scores.
	HealthScoreWindow = 5 * time.Minute
)

// StateMachine orchestrates DNS failover by evaluating provider health scores
// and driving transitions through the state lifecycle:
//
//	HEALTHY -> DEGRADED -> FAILING_OVER -> FAILED_OVER -> RECOVERING -> HEALTHY
type StateMachine struct {
	healthStore  HealthStore
	registrar    RegistrarClient
	stateStore   *StateStore
	safetyParams SafetyParams
}

// NewStateMachine creates a fully wired state machine. The Storage parameter
// is kept for backward compatibility (it holds the *sql.DB), but the actual
// health queries go through the HealthStore interface.
func NewStateMachine(storage *Storage, registrar RegistrarClient, healthStore HealthStore, stateStore *StateStore) *StateMachine {
	return &StateMachine{
		healthStore:  healthStore,
		registrar:    registrar,
		stateStore:   stateStore,
		safetyParams: DefaultSafetyParams,
	}
}

// Evaluate is the main tick function, called every 30 seconds by the main loop.
// It loads persisted state, delegates to the appropriate handler, and persists
// any changes.
func (sm *StateMachine) Evaluate(ctx context.Context) {
	state, err := sm.stateStore.Load()
	if err != nil {
		log.Printf("[StateMachine] ERROR loading state: %v", err)
		return
	}

	log.Printf("[StateMachine] Current state: %s (since %s)",
		state.CurrentState, state.LastTransitionTime.Format(time.RFC3339))

	switch state.CurrentState {
	case StateHealthy:
		sm.handleHealthy(ctx, state)
	case StateDegraded:
		sm.handleDegraded(ctx, state)
	case StateFailingOver:
		sm.handleFailingOver(ctx, state)
	case StateFailedOver:
		sm.handleFailedOver(ctx, state)
	case StateRecovering:
		sm.handleRecovering(ctx, state)
	default:
		log.Printf("[StateMachine] Unknown state %q, resetting to HEALTHY", state.CurrentState)
		sm.transition(state, StateHealthy)
	}
}

// handleHealthy queries provider health scores and transitions to DEGRADED
// if the primary provider score drops below the degrade threshold.
func (sm *StateMachine) handleHealthy(ctx context.Context, state *ControllerState) {
	scores, err := sm.healthStore.GetProviderHealthScores(ctx, HealthScoreWindow)
	if err != nil {
		log.Printf("[Healthy] ERROR fetching health scores: %v", err)
		return
	}

	primary := sm.findProvider(scores, state.PrimaryProviderID)
	if primary == nil {
		log.Printf("[Healthy] Primary provider %s not found in health scores", state.PrimaryProviderID)
		return
	}

	log.Printf("[Healthy] Primary provider %s score: %.3f (threshold: %.2f)",
		primary.ProviderName, primary.Score, DegradeThreshold)

	if primary.Score < DegradeThreshold {
		log.Printf("[Healthy] Primary score %.3f below threshold %.2f, transitioning to DEGRADED",
			primary.Score, DegradeThreshold)
		state.DegradedCheckCount = 1 // first degraded observation
		sm.transition(state, StateDegraded)
	}
}

// handleDegraded verifies that the primary provider degradation persists over
// consecutive checks. If the score recovers, we go back to HEALTHY. If it
// stays below threshold for ConsecutiveDegradedChecksRequired checks, we
// transition to FAILING_OVER.
func (sm *StateMachine) handleDegraded(ctx context.Context, state *ControllerState) {
	scores, err := sm.healthStore.GetProviderHealthScores(ctx, HealthScoreWindow)
	if err != nil {
		log.Printf("[Degraded] ERROR fetching health scores: %v", err)
		return
	}

	primary := sm.findProvider(scores, state.PrimaryProviderID)
	if primary == nil {
		log.Printf("[Degraded] Primary provider %s not found", state.PrimaryProviderID)
		return
	}

	log.Printf("[Degraded] Primary score: %.3f, consecutive degraded checks: %d/%d",
		primary.Score, state.DegradedCheckCount, ConsecutiveDegradedChecksRequired)

	if primary.Score >= DegradeThreshold {
		// Primary recovered. Reset counter and go back to HEALTHY.
		log.Printf("[Degraded] Primary recovered (score %.3f >= %.2f), returning to HEALTHY",
			primary.Score, DegradeThreshold)
		state.DegradedCheckCount = 0
		sm.transition(state, StateHealthy)
		return
	}

	// Still degraded. Increment the consecutive check counter.
	state.DegradedCheckCount++

	if state.DegradedCheckCount >= ConsecutiveDegradedChecksRequired {
		log.Printf("[Degraded] Degradation confirmed after %d consecutive checks, transitioning to FAILING_OVER",
			state.DegradedCheckCount)
		sm.transition(state, StateFailingOver)
		return
	}

	// Not yet confirmed -- persist the updated counter and wait.
	if err := sm.stateStore.Save(state); err != nil {
		log.Printf("[Degraded] ERROR saving state: %v", err)
	}
}

// handleFailingOver executes the DNS failover by updating nameservers at the
// registrar to point to the secondary provider, then verifying propagation.
func (sm *StateMachine) handleFailingOver(ctx context.Context, state *ControllerState) {
	log.Printf("[FailingOver] Executing failover for domain %s", state.Domain)

	// Step 1: Get current nameservers for audit trail.
	currentNS, err := sm.registrar.GetNameservers(state.Domain)
	if err != nil {
		log.Printf("[FailingOver] ERROR reading current nameservers: %v", err)
		// Abort to DEGRADED rather than retry in a tight loop.
		sm.transition(state, StateDegraded)
		return
	}
	log.Printf("[FailingOver] Current nameservers: %v", currentNS)

	// Step 2: Build the new nameserver list (secondary only).
	// In a real deployment, the secondary nameservers would be looked up from
	// configuration or the provider record. Here we use a simple convention.
	secondaryNS, err := sm.resolveSecondaryNameservers(ctx, state)
	if err != nil {
		log.Printf("[FailingOver] ERROR resolving secondary nameservers: %v", err)
		sm.transition(state, StateDegraded)
		return
	}

	// Step 3: Update nameservers at the registrar.
	log.Printf("[FailingOver] Updating nameservers to secondary: %v", secondaryNS)
	if err := sm.registrar.UpdateNameservers(state.Domain, secondaryNS); err != nil {
		log.Printf("[FailingOver] ERROR updating nameservers: %v", err)
		sm.transition(state, StateDegraded)
		return
	}

	// Step 4: Verify propagation.
	propagated, err := sm.registrar.VerifyPropagation(state.Domain, secondaryNS)
	if err != nil {
		log.Printf("[FailingOver] ERROR verifying propagation: %v", err)
		// The update was sent; move to FAILED_OVER anyway and let
		// monitoring detect if it actually took effect.
	}

	if propagated {
		log.Printf("[FailingOver] Propagation verified for domain %s", state.Domain)
	} else {
		log.Printf("[FailingOver] WARNING: propagation not yet confirmed, proceeding anyway")
	}

	// Step 5: Record failover metadata and transition.
	state.LastFailoverTime = time.Now()
	state.DailyFailoverCount++
	state.DegradedCheckCount = 0
	sm.transition(state, StateFailedOver)

	log.Printf("[FailingOver] Failover complete. Daily count: %d/%d",
		state.DailyFailoverCount, sm.safetyParams.MaxDailyFailovers)
}

// handleFailedOver monitors the primary provider for recovery while traffic
// is served by the secondary. When the primary score exceeds RecoveryThreshold,
// we transition to RECOVERING.
func (sm *StateMachine) handleFailedOver(ctx context.Context, state *ControllerState) {
	scores, err := sm.healthStore.GetProviderHealthScores(ctx, HealthScoreWindow)
	if err != nil {
		log.Printf("[FailedOver] ERROR fetching health scores: %v", err)
		return
	}

	primary := sm.findProvider(scores, state.PrimaryProviderID)
	if primary == nil {
		log.Printf("[FailedOver] Primary provider %s not found, staying in FAILED_OVER", state.PrimaryProviderID)
		return
	}

	secondary := sm.findProvider(scores, state.SecondaryProviderID)
	if secondary != nil {
		log.Printf("[FailedOver] Secondary provider %s score: %.3f", secondary.ProviderName, secondary.Score)
	}

	log.Printf("[FailedOver] Primary provider %s score: %.3f (recovery threshold: %.2f)",
		primary.ProviderName, primary.Score, RecoveryThreshold)

	if primary.Score > RecoveryThreshold {
		log.Printf("[FailedOver] Primary showing recovery (score %.3f > %.2f), transitioning to RECOVERING",
			primary.Score, RecoveryThreshold)
		state.RecoveryStartTime = time.Now()
		sm.transition(state, StateRecovering)
	}
}

// handleRecovering verifies that the primary provider remains stable for the
// full recovery cooldown period. If it stays healthy, we failback DNS to the
// primary and return to HEALTHY. If it degrades again during recovery, we
// abort back to FAILED_OVER.
func (sm *StateMachine) handleRecovering(ctx context.Context, state *ControllerState) {
	scores, err := sm.healthStore.GetProviderHealthScores(ctx, HealthScoreWindow)
	if err != nil {
		log.Printf("[Recovering] ERROR fetching health scores: %v", err)
		return
	}

	primary := sm.findProvider(scores, state.PrimaryProviderID)
	if primary == nil {
		log.Printf("[Recovering] Primary provider not found, aborting recovery")
		sm.transition(state, StateFailedOver)
		return
	}

	log.Printf("[Recovering] Primary score: %.3f, time in recovery: %s (need: %s)",
		primary.Score,
		time.Since(state.RecoveryStartTime).Round(time.Second),
		sm.safetyParams.RecoveryCooldown)

	// If primary degrades again during recovery, abort.
	if primary.Score < DegradeThreshold {
		log.Printf("[Recovering] Primary degraded again (score %.3f), aborting recovery", primary.Score)
		state.RecoveryStartTime = time.Time{}
		sm.transition(state, StateFailedOver)
		return
	}

	// Check if the cooldown period has elapsed.
	if time.Since(state.RecoveryStartTime) < sm.safetyParams.RecoveryCooldown {
		log.Printf("[Recovering] Still in cooldown, waiting...")
		return
	}

	// Cooldown elapsed and primary is healthy -- execute failback.
	log.Printf("[Recovering] Recovery cooldown complete, executing failback for %s", state.Domain)

	primaryNS, err := sm.resolvePrimaryNameservers(ctx, state)
	if err != nil {
		log.Printf("[Recovering] ERROR resolving primary nameservers: %v", err)
		return
	}

	if err := sm.registrar.UpdateNameservers(state.Domain, primaryNS); err != nil {
		log.Printf("[Recovering] ERROR updating nameservers for failback: %v", err)
		return
	}

	propagated, err := sm.registrar.VerifyPropagation(state.Domain, primaryNS)
	if err != nil {
		log.Printf("[Recovering] ERROR verifying failback propagation: %v", err)
	}
	if propagated {
		log.Printf("[Recovering] Failback propagation verified")
	} else {
		log.Printf("[Recovering] WARNING: failback propagation not yet confirmed")
	}

	state.DegradedCheckCount = 0
	state.RecoveryStartTime = time.Time{}
	sm.transition(state, StateHealthy)
	log.Printf("[Recovering] Failback complete, system is HEALTHY")
}

// transition validates the state change via safety checks, updates the
// persisted state, and logs the transition.
func (sm *StateMachine) transition(state *ControllerState, toState string) {
	if err := ValidateTransition(state, toState, sm.safetyParams); err != nil {
		log.Printf("[StateMachine] Transition %s -> %s BLOCKED: %v",
			state.CurrentState, toState, err)
		return
	}

	fromState := state.CurrentState
	state.CurrentState = toState
	state.LastTransitionTime = time.Now()

	if err := sm.stateStore.Save(state); err != nil {
		log.Printf("[StateMachine] ERROR persisting state after transition: %v", err)
		// State is in-memory correct but not persisted. Next tick will
		// re-load stale state. This is safe because the worst case is
		// re-evaluating the previous state.
		return
	}

	log.Printf("[StateMachine] Transition: %s -> %s", fromState, toState)
}

// findProvider returns the health entry for the given provider ID, or nil.
func (sm *StateMachine) findProvider(scores []ProviderHealth, providerID string) *ProviderHealth {
	for i := range scores {
		if scores[i].ProviderID == providerID {
			return &scores[i]
		}
	}
	return nil
}

// resolveSecondaryNameservers looks up the nameservers for the secondary
// provider. In a production system, these would come from the provider
// record in the database or from a configuration map. For now we use the
// registrar client to get current NS and filter to secondary.
func (sm *StateMachine) resolveSecondaryNameservers(ctx context.Context, state *ControllerState) ([]string, error) {
	// TODO: In production, query the dns_providers table for the secondary
	// provider's configured nameservers. For example:
	//   SELECT health_check_endpoints FROM dns_providers WHERE id = $1
	//
	// For the mock implementation, we return a well-known secondary set.
	_ = ctx
	if state.SecondaryProviderID == "" {
		return nil, fmt.Errorf("no secondary provider configured")
	}
	// The mock registrar will return both providers' NS. In a real
	// implementation, this would be provider-specific.
	return []string{"ns1.secondary-provider.com", "ns2.secondary-provider.com"}, nil
}

// resolvePrimaryNameservers is the inverse of resolveSecondaryNameservers.
func (sm *StateMachine) resolvePrimaryNameservers(ctx context.Context, state *ControllerState) ([]string, error) {
	_ = ctx
	if state.PrimaryProviderID == "" {
		return nil, fmt.Errorf("no primary provider configured")
	}
	return []string{"ns1.primary-provider.com", "ns2.primary-provider.com"}, nil
}
