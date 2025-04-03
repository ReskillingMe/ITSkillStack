# Checking VM OS Patches for a Specific OCI Instance Using OCI CLI

To display available OS patches for a specific OCI VM instance, you can use the OCI CLI with OS Management Service commands. Here's how to do it:

## Prerequisites
1. OCI CLI installed and configured
2. Necessary IAM permissions to access OS Management Service
3. Instance must have the OS Management Agent installed and running

## Steps to Check Available Patches

### 1. First, get your instance OCID:
```bash
oci compute instance list --compartment-id <your_compartment_ocid> --query "data[?\"display-name\"=='<your_instance_name>'].id" --output json
```

### 2. Check if the instance is managed by OS Management:
```bash
oci os-management managed-instance list --compartment-id <your_compartment_ocid> --query "data[?\"display-name\"=='<your_instance_name>']"
```

### 3. Get available updates for the instance:
```bash
oci os-management managed-instance get-update --managed-instance-id <managed_instance_ocid>
```

### 4. For more detailed patch information:
```bash
oci os-management software-package list-available-updates --managed-instance-id <managed_instance_ocid>
```

### 5. To filter by update type (security, bugfix, enhancement):
```bash
oci os-management software-package list-available-updates \
--managed-instance-id <managed_instance_ocid> \
--update-type SECURITY
```

## Example Workflow

```bash
# Get instance OCID
INSTANCE_OCID=$(oci compute instance list --compartment-id $COMPARTMENT_OCID --query "data[?\"display-name\"=='my-vm-instance'].id" --raw-output)

# Get managed instance OCID
MANAGED_INSTANCE_OCID=$(oci os-management managed-instance list --compartment-id $COMPARTMENT_OCID --query "data[?\"compute-instance-id\"=='$INSTANCE_OCID'].id" --raw-output)

# List all available updates
oci os-management software-package list-available-updates --managed-instance-id $MANAGED_INSTANCE_OCID --all

# List only security updates
oci os-management software-package list-available-updates \
--managed-instance-id $MANAGED_INSTANCE_OCID \
--update-type SECURITY \
--all
```

## Formatting Output

For better readability, you can format the output as a table:

```bash
oci os-management software-package list-available-updates --managed-instance-id $MANAGED_INSTANCE_OCID --all --output table --query "data [*].{PackageName:name, UpdateType:\"update-type\", Version:version}"
```

Note: If your instance isn't showing up in OS Management, ensure the OS Management Agent is installed and running on the VM.