package main

import (
	"errors"
	"time"
)

type SafetyParams struct {
	MinTimeInState     time.Duration
	FailoverCooldown   time.Duration
	MaxDailyFailovers  int
	RequireManualAuth  bool
}

var DefaultSafetyParams = SafetyParams{
	MinTimeInState:    5 * time.Minute,
	FailoverCooldown:  1 * time.Hour,
	MaxDailyFailovers: 1,
	RequireManualAuth: false, // Set to true for production initially
}

func ValidateTransition(fromState, toState string, lastTransition time.Time) error {
	// 1. Check Minimum Time in State
	if time.Since(lastTransition) < DefaultSafetyParams.MinTimeInState {
		return errors.New("minimum time in state not met")
	}

	// 2. Check Cooldown for Failover
	if toState == StateFailingOver {
		// In real impl, check last failover time from DB
		// if time.Since(lastFailover) < DefaultSafetyParams.FailoverCooldown { ... }
	}

	return nil
}
