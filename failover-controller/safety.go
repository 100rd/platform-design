package main

import (
	"fmt"
	"time"
)

// SafetyParams defines the guard rails that prevent the controller from
// oscillating between states or executing too many failovers.
type SafetyParams struct {
	MinTimeInState    time.Duration
	FailoverCooldown  time.Duration
	MaxDailyFailovers int
	RequireManualAuth bool
	RecoveryCooldown  time.Duration // time primary must be stable before failback
}

var DefaultSafetyParams = SafetyParams{
	MinTimeInState:    5 * time.Minute,
	FailoverCooldown:  1 * time.Hour,
	MaxDailyFailovers: 1,
	RequireManualAuth: false, // Set to true for production initially
	RecoveryCooldown:  10 * time.Minute,
}

// validTransitions defines which state transitions are allowed.
// Any transition not listed here is rejected.
var validTransitions = map[string][]string{
	StateHealthy:        {StateDegraded},
	StateDegraded:       {StateHealthy, StateFailingOver},
	StateFailingOver:    {StateFailedOver, StateDegraded}, // can abort back to degraded on failure
	StateFailedOver:     {StateRecovering},
	StateRecovering:     {StateHealthy, StateFailedOver}, // can fall back if primary degrades again
}

// ValidateTransition checks all safety invariants before allowing a state change.
// It returns a descriptive error if the transition is not permitted.
func ValidateTransition(state *ControllerState, toState string, params SafetyParams) error {
	fromState := state.CurrentState

	// 1. Check the transition is topologically valid.
	allowed, ok := validTransitions[fromState]
	if !ok {
		return fmt.Errorf("no transitions defined from state %s", fromState)
	}
	found := false
	for _, s := range allowed {
		if s == toState {
			found = true
			break
		}
	}
	if !found {
		return fmt.Errorf("transition from %s to %s is not allowed", fromState, toState)
	}

	// 2. Check minimum time in current state.
	elapsed := time.Since(state.LastTransitionTime)
	if elapsed < params.MinTimeInState {
		return fmt.Errorf(
			"minimum time in state not met: %s elapsed, need %s",
			elapsed.Round(time.Second), params.MinTimeInState,
		)
	}

	// 3. Enforce failover-specific cooldown and daily limit.
	if toState == StateFailingOver {
		if !state.LastFailoverTime.IsZero() {
			sinceLast := time.Since(state.LastFailoverTime)
			if sinceLast < params.FailoverCooldown {
				return fmt.Errorf(
					"failover cooldown not met: %s since last failover, need %s",
					sinceLast.Round(time.Second), params.FailoverCooldown,
				)
			}
		}

		if state.DailyFailoverCount >= params.MaxDailyFailovers {
			return fmt.Errorf(
				"daily failover limit reached: %d of %d",
				state.DailyFailoverCount, params.MaxDailyFailovers,
			)
		}
	}

	// 4. Manual authorization check (for production environments).
	if params.RequireManualAuth && toState == StateFailingOver {
		return fmt.Errorf("manual authorization required for failover (RequireManualAuth=true)")
	}

	return nil
}
