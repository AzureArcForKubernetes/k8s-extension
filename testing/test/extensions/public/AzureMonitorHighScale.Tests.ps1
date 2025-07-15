Describe 'Azure Monitor High Scale Mode Testing' {
    BeforeAll {
        $extensionType = "microsoft.azuremonitor.containers"
        $extensionName = "azuremonitor-containers"
        $extensionAgentName = "omsagent"
        $extensionAgentNamespace = "kube-system"
        
        . $PSScriptRoot/../../helper/Constants.ps1
        . $PSScriptRoot/../../helper/Helper.ps1
    }

    It 'Creates the extension with high log scale mode and verifies DCE creation' {
        # Create extension with high scale mode enabled
        az $Env:K8sExtensionName create -c $($ENVCONFIG.arcClusterName) -g $($ENVCONFIG.resourceGroup) `
            --cluster-type connectedClusters --extension-type $extensionType -n $extensionName `
            --configuration-settings "amalogs.enableHighLogScaleMode=true" --no-wait
        $? | Should -BeTrue

        # Verify extension creation
        $output = az $Env:K8sExtensionName show -c $($ENVCONFIG.arcClusterName) -g $($ENVCONFIG.resourceGroup) --cluster-type connectedClusters -n $extensionName
        $? | Should -BeTrue

        $extension = ($output | ConvertFrom-Json)
        $extension | Should -Not -BeNullOrEmpty
        
        # Verify high scale mode configuration
        $settings = $extension.configurationSettings
        $settings.'amalogs.enableHighLogScaleMode' | Should -Be "true"
        $settings.'amalogs.useAADAuth' | Should -Be "true"

        # Wait for extension to install
        $n = 0
        do {
            if (Has-ExtensionData $extensionName) {
                break
            }
            Start-Sleep -Seconds 10
            $n += 1
        } while ($n -le $MAX_RETRY_ATTEMPTS)
        $n | Should -BeLessOrEqual $MAX_RETRY_ATTEMPTS

        # Verify DCE creation
        $clusterLocation = (az resource show -g $($ENVCONFIG.resourceGroup) -n $($ENVCONFIG.arcClusterName) --resource-type "Microsoft.Kubernetes/connectedClusters" --query location -o tsv).ToLower()
        $dceName = "MSCI-ingest-$clusterLocation-$($ENVCONFIG.arcClusterName)"
        if ($dceName.Length -gt 43) {
            $dceName = $dceName.Substring(0, 43)
            # Remove trailing hyphen if present
            if ($dceName.EndsWith("-")) {
                $dceName = $dceName.Substring(0, $dceName.Length - 1)
            }
        }
        
        $dce = az monitor data-collection endpoint show -g $($ENVCONFIG.resourceGroup) -n $dceName
        $? | Should -BeTrue
        $dce | Should -Not -BeNullOrEmpty
        
        # Verify DCE configuration
        $dceObj = ($dce | ConvertFrom-Json)
        $dceObj.kind | Should -Be "Linux"
        $dceObj.properties.networkAcls.publicNetworkAccess | Should -Be "Enabled"
    }

    It "Verifies Data Collection Rule configuration for high scale mode" {
        # Get the DCR name
        $clusterLocation = (az resource show -g $($ENVCONFIG.resourceGroup) -n $($ENVCONFIG.arcClusterName) --resource-type "Microsoft.Kubernetes/connectedClusters" --query location -o tsv).ToLower()
        $dcrName = "MSCI-$clusterLocation-$($ENVCONFIG.arcClusterName)"
        if ($dcrName.Length -gt 64) {
            $dcrName = $dcrName.Substring(0, 64)
        }

        # Get the DCR
        $dcr = az monitor data-collection rule show -g $($ENVCONFIG.resourceGroup) -n $dcrName
        $? | Should -BeTrue
        $dcr | Should -Not -BeNullOrEmpty

        # Verify high scale mode streams configuration
        $dcrObj = ($dcr | ConvertFrom-Json)
        $streams = $dcrObj.properties.dataSources.extensions[0].streams
        $streams | Should -Contain "Microsoft-ContainerLogV2-HighScale"
        $streams | Should -Contain "Microsoft-KubeEvents"
        $streams | Should -Contain "Microsoft-KubePodInventory"
        $streams | Should -Contain "Microsoft-KubeNodeInventory"
        $streams | Should -Contain "Microsoft-KubePVInventory"
        $streams | Should -Contain "Microsoft-KubeServices"
        $streams | Should -Contain "Microsoft-KubeMonAgentEvents"
        $streams | Should -Contain "Microsoft-InsightsMetrics"
        $streams | Should -Contain "Microsoft-ContainerInventory"
        $streams | Should -Contain "Microsoft-ContainerNodeInventory"
        $streams | Should -Contain "Microsoft-Perf"
    }

    It "Deletes the extension and verifies DCE cleanup" {
        # Get DCE name before deletion
        $clusterLocation = (az resource show -g $($ENVCONFIG.resourceGroup) -n $($ENVCONFIG.arcClusterName) --resource-type "Microsoft.Kubernetes/connectedClusters" --query location -o tsv).ToLower()
        $dceName = "MSCI-ingest-$clusterLocation-$($ENVCONFIG.arcClusterName)"
        if ($dceName.Length -gt 43) {
            $dceName = $dceName.Substring(0, 43)
            # Remove trailing hyphen if present
            if ($dceName.EndsWith("-")) {
                $dceName = $dceName.Substring(0, $dceName.Length - 1)
            }
        }

        # Delete the extension
        $output = az $Env:K8sExtensionName delete -c $($ENVCONFIG.arcClusterName) -g $($ENVCONFIG.resourceGroup) --cluster-type connectedClusters -n $extensionName --force
        $? | Should -BeTrue

        # Verify extension is deleted
        $output = az $Env:K8sExtensionName show -c $($ENVCONFIG.arcClusterName) -g $($ENVCONFIG.resourceGroup) --cluster-type connectedClusters -n $extensionName
        $? | Should -BeFalse
        $output | Should -BeNullOrEmpty

        # Verify DCE is deleted
        $dce = az monitor data-collection endpoint show -g $($ENVCONFIG.resourceGroup) -n $dceName
        $? | Should -BeFalse
    }

    It "Performs another list after the delete" {
        $output = az $Env:K8sExtensionName list -c $($ENVCONFIG.arcClusterName) -g $($ENVCONFIG.resourceGroup) --cluster-type connectedClusters
        $? | Should -BeTrue
        $output | Should -Not -BeNullOrEmpty
        
        $extensionExists = $output | ConvertFrom-Json | Where-Object { $_.extensionType -eq $extensionName }
        $extensionExists | Should -BeNullOrEmpty
    }
}
