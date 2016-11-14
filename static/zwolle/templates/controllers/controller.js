/*
Controller for interface "$interfaceName$" (context: "$contextName$"). Generated code, edit with care.
$if(verbose)$Generated using template: $usedTemplate$
Generated by $ampersandVersionStr$

INTERFACE "$interfaceName$" : $expAdl$ :: $source$ * $target$  ($if(!isRoot)$non-$endif$root interface)
Roles: [$roles;separator=", "$]
$endif$*/
/* jshint ignore:start */
AmpersandApp.controller('$interfaceName$Controller', function (\$scope, \$rootScope, \$route, \$routeParams, \$sessionStorage, ResourceService) {
    const resourceType = '$source$';
    const ifcName = '$interfaceName$';
    let resourceId;
    
    if(\$routeParams['new'] && '$source$' == '$target$') resourceId = '_NEW'; // Set resourceId to special '_NEW' value in case new resource must be created 
    else if(resourceType == 'SESSION') resourceId = \$sessionStorage.session.id;
    else if (resourceType == 'ONE') resourceId = '1';
    else resourceId = \$routeParams.resourceId;
    
    \$scope.resource =  { '_id_' : resourceId
                        , '_path_' : '/resources/' + resourceType + '/' + resourceId
                        , '_isRoot_' : true
                        , ifcName : {}
                        };
    
    // Create new resource
    if(\$routeParams['new']) ResourceService.createResource(\$scope.resource, ifcName, \$scope.resource);
    
    // Get resource interface data
    else ResourceService.getResource(\$scope.resource, ifcName, \$scope.resource);
    
});
/* jshint ignore:end */