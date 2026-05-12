Compartiments = @{

    Network = @{
        Name        = 'cmp-network'
        Description = 'Couche réseau OCI (VCN, subnets, NSG, routes, gateways)'
        OCID        = 'ocid1.compartment.oc1..network123'
    }

    Plateforme = @{
        NonProd = @{
            Name        = 'cmp-plateforme-nonprod'
            Description = 'Serveurs applicatifs et BD : DEV / TEST / PREPROD'
            OCID        = 'ocid1.compartment.oc1..platnp456'
        }
        Prod = @{
            Name        = 'cmp-plateforme-prod'
            Description = 'Serveurs applicatifs et BD : PROD + DR'
            OCID        = 'ocid1.compartment.oc1..platprod789'
        }
    }

    Certificats = @{
        NonProd = @{
            Name        = 'cmp-certificats-nonprod'
            Description = 'Certificats DEV / TEST / PREPROD'
            OCID        = 'ocid1.compartment.oc1..certnp111'
        }
        Prod = @{
            Name        = 'cmp-certificats-prod'
            Description = 'Certificats PROD'
            OCID        = 'ocid1.compartment.oc1..certp222'
        }
    }

    Shared = @{
        Name        = 'cmp-shared'
        Description = 'Services transverses : OEM, IDM, Control-M, etc.'
        OCID        = 'ocid1.compartment.oc1..shared333'
    }
}