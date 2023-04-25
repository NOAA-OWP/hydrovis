# Naming Schema

## Global Resources

`hv-vpp-${var.environment}-${var.region}-${name}`

## Region Specific Resources

`hv-vpp-${var.environment}-${name}`


# Resources that need name updates:
- IAM
  - Roles
    - `HydrovisESRISSMDeploy_${var.region}` => `hv-vpp-${var.environment}-${var.region}-egis`
- S3
  - Bucket Names
    - `hydrovis-${var.environment}-${var.name}-${var.region}` => `hv-vpp-${var.environment}-${var.region}-${var.name}`
- eGIS
  - Bucket Names
    - `hydrovis-${var.environment}-egis-${var.region}-${var.name_suffix}` => `hv-vpp-${var.environment}-${var.region}-egis-${var.name_suffix}`
- ImageBuilder