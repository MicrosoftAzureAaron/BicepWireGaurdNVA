@description('Name of the Virtual Network')
var vnetName = 'HaTest'

@description('Azure Address space for the Virtual Network')
param vnetAddressSpace string = '100.127.0.0/24'

@description('Subnet name')
var subnetName = 'WGNVA'

@description('Subnet address prefix')
param subnetAddressPrefix string = '100.127.0.0/24'
