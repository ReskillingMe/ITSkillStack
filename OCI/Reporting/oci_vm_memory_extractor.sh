#!/bin/bash

# OCI VM Host Memory Usage Extractor
# Extracts memory metrics and top processes for a specific VM instance from OCI Monitoring
# Output: CSV file with Date, Time, Memory Usage (%), Available Memory (MB), Used Memory (MB), Top 3 Processes

# Configuration - UPDATE THESE VALUES
COMPARTMENT_ID="ocid1.compartment.oc1..your_compartment_id"
INSTANCE_ID="ocid1.instance.oc1..your_instance_id"
INSTANCE_NAME="your-vm-hostname"  # For display purposes
OUTPUT_FILE="oci_vm_memory_usage_${INSTANCE_NAME}_$(date +%Y%m%d).csv"
DAYS_TO_FETCH=3       # Number of days of historical data to fetch
RESOLUTION="1h"       # 1h (hourly), 5m (5-minute), etc.
OCI_CLI_PROFILE="DEFAULT"  # Your OCI CLI profile name

# Validate OCI CLI is installed
if ! command -v oci &> /dev/null; then
    echo "Error: OCI CLI is not installed. Please install it first."
    exit 1
fi

# Validate jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it first (sudo apt-get install jq)."
    exit 1
fi

# Calculate time range
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -d "$DAYS_TO_FETCH days ago" +"%Y-%m-%dT%H:%M:%SZ")

# CSV Header
echo "Date,Time,InstanceName,MemoryUtilization(%),AvailableMemory(MB),UsedMemory(MB),TopProcess1,TopProcess2,TopProcess3" > "$OUTPUT_FILE"

# Function to fetch OCI metrics with error handling
fetch_oci_metrics() {
    local query="$1"
    local start_time="$2"
    local end_time="$3"

    oci monitoring metric-data summarize-metrics-data \
        --compartment-id "$COMPARTMENT_ID" \
        --namespace "oci_computeagent" \
        --query-text "$query" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --resolution "$RESOLUTION" \
        --profile "$OCI_CLI_PROFILE" \
        --query "data[?contains(name,'MemoryUtilization')].aggregated-datapoints[] | [?value!='null'] | sort_by(&timestamp)" \
        --output json 2>/dev/null
}

# Function to get top processes for a specific timestamp
get_top_processes() {
    local timestamp="$1"

    local process_data=$(oci monitoring metric-data summarize-metrics-data \
        --compartment-id "$COMPARTMENT_ID" \
        --namespace "oci_computeagent" \
        --query-text "TopProcess{resourceId=\"$INSTANCE_ID\"}.mean()" \
        --start-time "$(date -u -d "$timestamp - 5 minutes" +"%Y-%m-%dT%H:%M:%SZ")" \
        --end-time "$(date -u -d "$timestamp + 5 minutes" +"%Y-%m-%dT%H:%M:%SZ")" \
        --profile "$OCI_CLI_PROFILE" \
        --query "data[].aggregated-datapoints[] | [?value!='null'] | sort_by(&timestamp) | [0]" \
        --output json 2>/dev/null)

    echo "$process_data"
}

# Main processing
echo "Fetching memory usage data for instance: $INSTANCE_NAME (ID: $INSTANCE_ID)"
echo "Time range: $START_TIME to $END_TIME with $RESOLUTION resolution"

# Get memory utilization metrics
MEMORY_DATA=$(fetch_oci_metrics "MemoryUtilization{resourceId=\"$INSTANCE_ID\"}.mean(),MemoryAvailable{resourceId=\"$INSTANCE_ID\"}.mean(),MemoryUsed{resourceId=\"$INSTANCE_ID\"}.mean()" "$START_TIME" "$END_TIME")

if [ -z "$MEMORY_DATA" ]; then
    echo "Error: No memory data returned. Check your:"
    echo "1. OCI CLI configuration"
    echo "2. Compartment and Instance IDs"
    echo "3. Ensure monitoring agent is running on the VM"
    exit 1
fi

# Process each timestamp
declare -a timestamps
mapfile -t timestamps < <(jq -r '.[].timestamp' <<< "$MEMORY_DATA")

for timestamp in "${timestamps[@]}"; do
    # Parse the timestamp
    date_part=$(date -d "$timestamp" +"%Y-%m-%d")
    time_part=$(date -d "$timestamp" +"%H:%M:%S")

    # Get memory values
    mem_util=$(jq -r ".[] | select(.timestamp==\"$timestamp\") | .value" <<< "$MEMORY_DATA" | head -1)
    mem_avail=$(jq -r ".[] | select(.timestamp==\"$timestamp\") | .value" <<< "$MEMORY_DATA" | sed -n '2p')
    mem_used=$(jq -r ".[] | select(.timestamp==\"$timestamp\") | .value" <<< "$MEMORY_DATA" | sed -n '3p')

    # Get top processes
    process_data=$(get_top_processes "$timestamp")
    process1=$(jq -r '.value | fromjson? | .[0].processName + "(" + (.[0].memoryUtilization | tostring) + "%)"' <<< "$process_data" 2>/dev/null || echo "N/A")
    process2=$(jq -r '.value | fromjson? | .[1].processName + "(" + (.[1].memoryUtilization | tostring) + "%)"' <<< "$process_data" 2>/dev/null || echo "N/A")
    process3=$(jq -r '.value | fromjson? | .[2].processName + "(" + (.[2].memoryUtilization | tostring) + "%)"' <<< "$process_data" 2>/dev/null || echo "N/A")

    # Write to CSV
    echo "$date_part,$time_part,$INSTANCE_NAME,$mem_util,$mem_avail,$mem_used,\"$process1\",\"$process2\",\"$process3\"" >> "$OUTPUT_FILE"

    # Progress indicator
    echo -n "."
done

echo -e "\n\nData collection complete. Results saved to: $OUTPUT_FILE"
echo -e "\nSample of collected data:"
head -5 "$OUTPUT_FILE" | column -t -s, | sed 's/^/  /'

