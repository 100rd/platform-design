#!/bin/bash
set -e

# Configuration
DOMAINS=("example.com")
PROVIDERS=("ns1.cloudflare.com" "ns1.route53.aws.com")
RECORD_TYPES=("A" "TXT" "CNAME")

echo "Starting DNS Drift Detection..."

for domain in "${DOMAINS[@]}"; do
    echo "Checking domain: $domain"
    
    # Create temp files for each provider's output
    for provider in "${PROVIDERS[@]}"; do
        echo "Querying provider: $provider"
        > "/tmp/${provider}_${domain}.txt"
        
        for type in "${RECORD_TYPES[@]}"; do
            # Dig, sort output to ensure deterministic comparison
            dig @$provider $domain $type +short +norecurse | sort >> "/tmp/${provider}_${domain}.txt"
        done
    done

    # Compare outputs
    base_provider=${PROVIDERS[0]}
    drift_detected=false
    
    for i in "${!PROVIDERS[@]}"; do
        if [ $i -eq 0 ]; then continue; fi
        
        current_provider=${PROVIDERS[$i]}
        diff_output=$(diff "/tmp/${base_provider}_${domain}.txt" "/tmp/${current_provider}_${domain}.txt")
        
        if [ ! -z "$diff_output" ]; then
            echo "DRIFT DETECTED between $base_provider and $current_provider for $domain"
            echo "$diff_output"
            drift_detected=true
            
            # TODO: Emit metric or log to DB
            # psql -c "INSERT INTO dns_sync_issues ..."
        fi
    done
    
    if [ "$drift_detected" = false ]; then
        echo "No drift detected for $domain"
    fi
done
