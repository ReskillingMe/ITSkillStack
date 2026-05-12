### Manifeste OCI All in One

```powershell
@{
    ###########################################################################
    # META
    ###########################################################################
    Meta = @{
        Version     = '4.0.0'
        Description = 'Manifeste All-in-One : source de vérité pour NSG, Routes, Palo Alto, Audit, Documentation, multi-IPs, multi-instances, multi-régions'
        Mainteneur  = 'Equipe DevSecOps'
        DerniereMaj = (Get-Date)
    }

    ###########################################################################
    # REGIONS
    ###########################################################################
    Regions = @{
        Description = 'Régions OCI utilisées pour production et reprise après sinistre.'
        Primaire = @{
            Nom         = 'ca-montreal-1'
            Code        = 'mtl'
            Description = 'Région principale hébergeant les ressources primaires.'
        }
        DR = @{
            Nom         = 'ca-toronto-1'
            Code        = 'tor'
            Description = 'Région secondaire dédiée à la reprise après sinistre (DR).'
        }
    }

    ###########################################################################
    # ENVIRONNEMENTS ET INSTANCES
    ###########################################################################
    Environnements = @{
        Description = 'Environnements logiques et instances applicatives par environnement.'
        DEV = @{
            Code        = 'dev'
            Region      = 'ca-montreal-1'
            Instances   = @('dev1','dev2','dev3')
            Description = 'Environnement de développement multi-instances.'
        }
        TEST = @{
            Code        = 'tst'
            Region      = 'ca-montreal-1'
            Instances   = @('test1','test2')
            Description = 'Environnement de tests fonctionnels.'
        }
        PREPROD = @{
            Code        = 'ppd'
            Region      = 'ca-montreal-1'
            Instances   = @('ppd1')
            Description = 'Environnement de pré-production.'
        }
        PROD = @{
            Code        = 'prd'
            Region      = 'ca-montreal-1'
            DRRegion    = 'ca-toronto-1'
            Instances   = @('prod1')
            Description = 'Environnement de production avec réplication DR multi-régions.'
        }
    }

    ###########################################################################
    # FLUX SOURCES (MULTI-IPs)
    ###########################################################################
    FluxSources = @{
        Description = 'Adresses IP sources par type de flux et par environnement (liste multi-IPs).'

        SMTP = @{
            Description = 'Serveurs SMTP pour envoi de courriels applicatifs.'
            DEV  = @{ IPs = @('10.10.10.10','10.10.10.11') }
            TEST = @{ IPs = @('10.20.20.20','10.20.20.21') }
            PROD = @{ IPs = @('10.30.30.30','10.30.30.31','10.30.30.32') }
        }

        IDM = @{
            Description = 'Serveurs IDM (OID/OAM) pour authentification et SSO.'
            DEV  = @{ IPs = @('10.11.11.11','10.11.11.12') }
            TEST = @{ IPs = @('10.21.21.21','10.21.21.22') }
            PROD = @{ IPs = @('10.31.31.31','10.31.31.32') }
        }

        OEM = @{
            Description = 'OEM OMS + Agents : monitoring, préparation CEMLI, déploiements Non-Prod EBS.'
            DEV  = @{ IPs = @('10.12.12.12','10.12.12.13') }
            TEST = @{ IPs = @('10.22.22.22','10.22.22.23') }
            PROD = @{ IPs = @('10.32.32.32','10.32.32.33','10.32.32.34') }
        }

        DB = @{
            Description = 'Serveurs Oracle DB standard.'
            DEV  = @{ IPs = @('10.13.13.10','10.13.13.11') }
            TEST = @{ IPs = @('10.23.23.10','10.23.23.11') }
            PROD = @{ IPs = @('10.33.33.10','10.33.33.11') }
        }

        Exadata = @{
            Description = 'Cluster Exadata (cell servers, compute nodes).'
            DEV  = @{ IPs = @('10.14.14.10','10.14.14.11','10.14.14.12') }
            TEST = @{ IPs = @('10.24.24.10','10.24.24.11','10.24.24.12') }
            PROD = @{ IPs = @('10.34.34.10','10.34.34.11','10.34.34.12') }
        }

        PISE = @{
            Description = 'Point d’intégration bancaire / interbancaire.'
            DEV  = @{ IPs = @('10.15.15.10') }
            TEST = @{ IPs = @('10.25.25.10') }
            PROD = @{ IPs = @('10.35.35.10','10.35.35.11') }
        }

        Citrix = @{
            Description = 'Infrastructure Citrix / VDI (accès utilisateur).'
            DEV  = @{ IPs = @('10.16.16.10','10.16.16.11') }
            TEST = @{ IPs = @('10.26.26.10','10.26.26.11') }
            PROD = @{ IPs = @('10.36.36.10','10.36.36.11','10.36.36.12') }
        }

        CTM = @{
            Description = 'Control-M : ordonnanceur batch et agents.'
            DEV  = @{ IPs = @('10.17.17.10','10.17.17.11') }
            TEST = @{ IPs = @('10.27.27.10','10.27.27.11') }
            PROD = @{ IPs = @('10.37.37.10','10.37.37.11','10.37.37.12') }
        }
    }

    ###########################################################################
    # MODELES DE FLUX (NORMS)
    ###########################################################################
    ModeleFlux = @{
        Description = 'Normes techniques pour chaque type de flux (protocoles, ports, sens, audit).'

        SMTP = @{
            Description = 'Flux SMTP pour envoi de courriels.'
            Protocol = 'TCP'
            Ports    = @(25,587)
            Sens     = 'Sortant'
            Zones    = @{ Source='App'; Cible='MailGateway' }
            MultiIPs = $true
            Audit = @{
                MustExist = $true
                MustMatchSourceIPs = $true
                MustMatchPorts = $true
                ForbiddenInterRegion = $true
            }
        }

        IDM = @{
            Description = 'Flux IDM pour authentification et SSO.'
            Protocol = 'HTTPS'
            Ports    = @(443)
            Sens     = 'Interne'
            Zones    = @{ Source='App'; Cible='Identity' }
            MultiIPs = $true
            Audit = @{
                MustExist = $true
                MustMatchSourceIPs = $true
                MustMatchPorts = $true
                ForbiddenInterRegion = $true
            }
        }

        OEM = @{
            Description = 'OEM : monitoring, agents, CEMLI, déploiements Non-Prod EBS.'
            Protocol = 'TCP'
            Ports    = @(3872,1521,22,1159)
            Sens     = 'Interne'
            Zones    = @{ Source='Monitoring'; Cible='App/DB/Infra' }
            MultiIPs = $true
            Audit = @{
                MustExist = $true
                MustMatchSourceIPs = $true
                MustMatchPorts = $true
                AllowedInterRegion = $true
            }
        }

        DB = @{
            Description = 'Flux Oracle DB standard.'
            Protocol = 'TCP'
            Ports    = @(1521)
            Sens     = 'Interne'
            Zones    = @{ Source='App'; Cible='DB' }
            MultiIPs = $true
            Audit = @{
                MustExist = $true
                MustMatchSourceIPs = $true
            }
        }

        Exadata = @{
            Description = 'Flux Exadata (RAC, ASM, cell servers).'
            Protocol = 'TCP'
            Ports    = @(1521,3260,3872)
            Sens     = 'Interne'
            Zones    = @{ Source='App'; Cible='Exadata' }
            MultiIPs = $true
            Audit = @{
                MustExist = $true
                MustMatchSourceIPs = $true
            }
        }

        PISE = @{
            Description = 'Flux d’intégration bancaire sécurisé.'
            Protocol = 'HTTPS'
            Ports    = @(443)
            Sens     = 'Sortant'
            Zones    = @{ Source='App'; Cible='PISE' }
            MultiIPs = $true
        }

        Citrix = @{
            Description = 'Flux Citrix pour accès VDI.'
            Protocol = 'TCP'
            Ports    = @(1494,2598,443)
            Sens     = 'Entrant'
            Zones    = @{ Source='Citrix'; Cible='App' }
            MultiIPs = $true
        }

        CTM = @{
            Description = 'Flux Control-M pour ordonnanceur et agents.'
            Protocol = 'TCP'
            Ports    = @(7005,7006,7007)
            Sens     = 'Interne'
            Zones    = @{ Source='ControlM'; Cible='App' }
            MultiIPs = $true
        }
    }

    ###########################################################################
    # ROUTE TARGETS (DESTINATIONS NORMALISEES)
    ###########################################################################
    RouteTargets = @{
        Description = 'Destinations de routage normalisées et next-hops (incluant Palo Alto).'

        Internet = @{
            Description = 'Sortie Internet sécurisée via Palo Alto.'
            CIDR = '0.0.0.0/0'
            NextHop = 'PaloAlto'
        }

        FusionApps = @{
            Description = 'Flux Oracle Fusion SaaS via Palo Alto.'
            CIDR = '129.146.0.0/16'
            NextHop = 'PaloAlto'
        }

        Citrix = @{
            Description = 'Accès Citrix/VDI via Palo Alto.'
            CIDR = '10.200.0.0/16'
            NextHop = 'PaloAlto'
        }

        SSH = @{
            Description = 'Accès SSH externe via Palo Alto.'
            CIDR = '0.0.0.0/0'
            NextHop = 'PaloAlto'
        }

        DRG = @{
            Description = 'Routage vers DataCenter On-Prem via DRG.'
            CIDR = '10.0.0.0/8'
            NextHop = 'DRG'
        }

        OCIInternal = @{
            Description = 'Services OCI internes (Object Storage, Vault, Logging) via Service Gateway.'
            CIDR = 'all-oci-services'
            NextHop = 'ServiceGateway'
        }

        DB = @{
            Description = 'Réseau des bases Oracle.'
            CIDR = '192.168.200.0/24'
            NextHop = 'PrivateSubnet'
        }

        Exadata = @{
            Description = 'Réseau Exadata (RAC/ASM).'
            CIDR = '192.168.100.0/24'
            NextHop = 'PrivateSubnet'
        }

        CTM = @{
            Description = 'Réseau Control-M interne.'
            CIDR = '192.168.50.0/24'
            NextHop = 'DRG'
        }
    }

    ###########################################################################
    # MODELE ROUTES (NORMS PAR TYPE DE SUBNET)
    ###########################################################################
    ModeleRoutes = @{
        Description = 'Normes de routage par type de subnet et règles Palo Alto.'

        Web = @{
            Description = 'Subnets Web exposés ; tout trafic externe passe par Palo Alto.'
            MustHave = @('Internet','FusionApps','Citrix','DRG')
            Forbidden = @('DB','Exadata')
        }

        App = @{
            Description = 'Subnets applicatifs internes ; inter-services bypass Palo Alto.'
            MustHave = @('DRG','OCIInternal','DB','Exadata','CTM')
            Forbidden = @('Internet','FusionApps','Citrix')
        }

        DB = @{
            Description = 'Subnets DB sécurisés ; pas d’accès direct Internet.'
            MustHave = @('DRG')
            Forbidden = @('Internet','NAT','FusionApps','Citrix')
        }

        Exadata = @{
            Description = 'Subnets Exadata ; accès restreint.'
            MustHave = @('DRG')
            Forbidden = @('Internet','NAT')
        }

        Batch = @{
            Description = 'Subnets Batch / Control-M.'
            MustHave = @('CTM','DRG')
            Forbidden = @('Internet')
        }
    }

    ###########################################################################
    # ROUTE BINDING RULES (PAR APPLICATION ET SUBNET TYPE)
    ###########################################################################
    RouteBindingRules = @{
        Description = 'Règles d’association des routes aux subnets par application.'

        EBS = @{
            Description = 'EBS : accès Fusion, DB, Exadata, CTM ; Web via Palo Alto.'
            SubnetTypes = @{
                Web = @('Internet','FusionApps','Citrix','DRG')
                App = @('DRG','OCIInternal','DB','Exadata','CTM')
                DB  = @('DRG')
            }
        }

        OBIEE = @{
            Description = 'OBIEE : BI, DB, CTM, Citrix.'
            SubnetTypes = @{
                Web = @('Internet','Citrix','DRG')
                App = @('DRG','OCIInternal','DB','CTM')
            }
        }

        Hyperion = @{
            Description = 'Hyperion : EPM, DB, CTM.'
            SubnetTypes = @{
                App = @('DRG','OCIInternal','DB','CTM')
            }
        }

        OFSAA = @{
            Description = 'OFSAA : Exadata, DB, CTM.'
            SubnetTypes = @{
                App = @('DRG','OCIInternal','DB','Exadata','CTM')
            }
        }

        OIC = @{
            Description = 'OIC : intégration, FusionApps, CTM.'
            SubnetTypes = @{
                App = @('DRG','OCIInternal','FusionApps','CTM')
            }
        }

        Shared = @{
            Description = 'Services partagés et composants transverses.'
            ControlM = @{
                Description = 'Control-M : ordonnanceur batch.'
                SubnetTypes = @{
                    Batch = @('CTM','DRG')
                }
            }
            IDM = @{
                Description = 'Identity Management interne.'
                SubnetTypes = @{
                    App = @('DRG','OCIInternal')
                }
            }
            OEM = @{
                Description = 'OEM : monitoring et EBS extension.'
                SubnetTypes = @{
                    App = @('DRG','OCIInternal','DB','Exadata')
                }
            }
        }
    }

    ###########################################################################
    # ROUTING POLICIES (PALO ALTO, ENVIRONNEMENT PROD vs NON-PROD)
    ###########################################################################
    RoutingPolicies = @{
        Description = 'Politiques globales de routage incluant Palo Alto, distinction PROD / NON-PROD.'

        PaloAlto = @{
            Description = 'Définition des flux qui doivent passer par le Palo Alto et ceux qui en sont exclus.'
            MustPassThrough = @('Internet','FusionApps','Citrix','SSH','ExternalAPIs','ExternalPartners')
            Bypass = @('InterService','OCIInternal','Monitoring','Batch','IDMInternal')
            Note = 'Les flux inter-services (App→DB, App→Exadata, App→OIC, etc.) sont exclus du passage Palo Alto.'
        }

        Environnements = @{
            PROD = @{
                Description = 'PROD : double région (Primaire + DR). Certaines routes doivent être répliquées vers la DR.'
                RegionPrimaire = 'ca-montreal-1'
                RegionDR       = 'ca-toronto-1'
                MustRouteToDR  = @('DB','Exadata','OEM','CTM')
                ForbiddenDR    = @('Internet','Citrix')
            }
            NONPROD = @{
                Description = 'DEV/TEST/PREPROD : mono-région ; les ressources restent locales.'
                MustStayLocal = @('DB','Exadata','OEM','CTM')
                Forbidden = @('DR')
            }
        }
    }

    ###########################################################################
    # APPLICATIONS (MULTI-INSTANCES)
    ###########################################################################
    Applications = @{
        Description = 'Catalogue des applications, instances et flux associés.'

        EBS = @{
            Description = 'Oracle E-Business Suite (ERP).'
            Instances = @('dev1','dev2','dev3','test1','test2','ppd1','prod1')
            FluxTypes = @('SMTP','IDM','OEM','DB','Exadata','PISE','CTM','Citrix')
        }

        OBIEE = @{
            Description = 'Oracle Business Intelligence.'
            Instances = @('dev1','dev2','test1','prod1')
            FluxTypes = @('SMTP','IDM','OEM','DB','CTM','Citrix')
        }

        Hyperion = @{
            Description = 'Oracle Hyperion (EPM).'
            Instances = @('dev1','test1','prod1')
            FluxTypes = @('SMTP','IDM','OEM','DB','CTM','Citrix')
        }

        OFSAA = @{
            Description = 'Oracle Financial Services Analytical Applications.'
            Instances = @('dev1','test1','prod1')
            FluxTypes = @('SMTP','IDM','OEM','DB','Exadata','PISE','CTM','Citrix')
        }

        OIC = @{
            Description = 'Oracle Integration Cloud (On-Prem).'
            Instances = @('dev1','test1','prod1')
            FluxTypes = @('SMTP','IDM','OEM','PISE','CTM','Citrix')
        }

        Shared = @{
            Description = 'Composants partagés transverses.'
            ControlM = @{
                Description = 'Ordonnanceur batch Control-M.'
                Instances = @('dev1','test1','prod1')
                FluxTypes = @('SMTP','OEM','CTM')
            }
            IDM = @{
                Description = 'Identity Management (OID/OAM).'
                Instances = @('dev1','test1','prod1')
                FluxTypes = @('IDM')
            }
            OEM = @{
                Description = 'Oracle Enterprise Manager (Monitoring + CEMLI + Déploiements EBS).'
                Instances = @('dev1','test1','prod1')
                FluxTypes = @('OEM')
                Fonctions = @{
                    Monitoring = @('Supervision DB','Supervision Exadata','Supervision Compute','Supervision Middle Tier')
                    EBS_Extension = @('Préparation des CEMLI','Déploiement Non-Prod EBS','Collecte des métriques EBS','Analyse des performances EBS')
                    Agents = @('Agent OEM sur DB','Agent OEM sur App Tier','Agent OEM sur OIC','Agent OEM sur Control-M')
                }
            }
        }
    }

    ###########################################################################
    # AUDIT RULES (NSG ET ROUTES)
    ###########################################################################
    AuditRules = @{
        Description = 'Règles d’audit pour valider conformité NSG et tables de routage, incluant Palo Alto et DR.'

        NSG = @{
            Description = 'Validation des règles NSG par rapport au manifeste.'
            ValidateFlux = $true
            ValidateSourceIPs = $true
            ValidatePorts = $true
            DetectUnexpectedRules = $true
            EnforceRegionRules = $true
            Notes = 'Les règles NSG doivent référencer les IPs listées dans FluxSources pour l’environnement correspondant.'
        }

        Routes = @{
            Description = 'Validation des tables de routage par rapport aux RouteBindingRules et RoutingPolicies.'
            ValidateMandatoryRoutes = $true
            DetectUnexpectedRoutes = $true
            ValidateNextHop = $true
            ValidateForbiddenRoutes = $true
            ValidateZoneRouting = $true
            PaloAlto = @{
                MustPassThrough = $true
                BypassList = $ManifesteRoutingBypass = @('InterService','OCIInternal','Monitoring','Batch','IDMInternal')
            }
            DR = @{
                ValidateDRReplication = $true
                PROD = @{
                    MustRouteToDR = @('DB','Exadata','OEM','CTM')
                    ForbiddenDR = @('Internet','Citrix')
                }
                NONPROD = @{
                    MustStayLocal = @('DB','Exadata','OEM','CTM')
                }
            }
        }
    }

    ###########################################################################
    # DOCUMENTATION
    ###########################################################################
    Documentation = @{
        Description = 'Paramètres pour génération automatique de documentation et rapports d’audit.'
        Sections = @('Résumé','Flux attendus','Routes attendues','Deltas','Actions recommandées','Historique')
        ReportFormat = 'Markdown'
        ReportPath = './reports'
    }
}
```

