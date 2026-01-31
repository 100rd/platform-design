package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"
)

// ControllerState is the persisted snapshot of the state machine.
// It is written to disk as JSON after every state transition so the
// controller can resume from the correct state after a restart.
type ControllerState struct {
	CurrentState          string    `json:"current_state"`
	PrimaryProviderID     string    `json:"primary_provider_id"`
	SecondaryProviderID   string    `json:"secondary_provider_id"`
	Domain                string    `json:"domain"`
	LastTransitionTime    time.Time `json:"last_transition_time"`
	LastFailoverTime      time.Time `json:"last_failover_time"`
	DailyFailoverCount    int       `json:"daily_failover_count"`
	DailyFailoverResetDay int       `json:"daily_failover_reset_day"` // day-of-year
	DegradedCheckCount    int       `json:"degraded_check_count"`     // consecutive degraded checks
	RecoveryStartTime     time.Time `json:"recovery_start_time"`
	UpdatedAt             time.Time `json:"updated_at"`
}

// StateStore handles loading and saving the controller state to a JSON file.
type StateStore struct {
	path string
	mu   sync.Mutex
}

// NewStateStore creates a StateStore that reads/writes state to the given path.
func NewStateStore(path string) *StateStore {
	return &StateStore{path: path}
}

// Load reads the persisted state from disk. If the file does not exist,
// it returns a default HEALTHY state so the controller starts clean.
func (ss *StateStore) Load() (*ControllerState, error) {
	ss.mu.Lock()
	defer ss.mu.Unlock()

	data, err := os.ReadFile(ss.path)
	if err != nil {
		if os.IsNotExist(err) {
			return ss.defaultState(), nil
		}
		return nil, fmt.Errorf("read state file %s: %w", ss.path, err)
	}

	var state ControllerState
	if err := json.Unmarshal(data, &state); err != nil {
		// Corrupt file -- start fresh rather than crash.
		return ss.defaultState(), nil
	}

	// Reset daily failover count if the day has rolled over.
	today := time.Now().YearDay()
	if state.DailyFailoverResetDay != today {
		state.DailyFailoverCount = 0
		state.DailyFailoverResetDay = today
	}

	return &state, nil
}

// Save persists the current state to disk atomically (write-to-temp then rename).
func (ss *StateStore) Save(state *ControllerState) error {
	ss.mu.Lock()
	defer ss.mu.Unlock()

	state.UpdatedAt = time.Now()

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal state: %w", err)
	}

	tmpPath := ss.path + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0644); err != nil {
		return fmt.Errorf("write temp state file: %w", err)
	}

	if err := os.Rename(tmpPath, ss.path); err != nil {
		return fmt.Errorf("rename state file: %w", err)
	}

	return nil
}

func (ss *StateStore) defaultState() *ControllerState {
	now := time.Now()
	return &ControllerState{
		CurrentState:          StateHealthy,
		PrimaryProviderID:     os.Getenv("PRIMARY_PROVIDER_ID"),
		SecondaryProviderID:   os.Getenv("SECONDARY_PROVIDER_ID"),
		Domain:                os.Getenv("FAILOVER_DOMAIN"),
		LastTransitionTime:    now,
		DailyFailoverResetDay: now.YearDay(),
	}
}
