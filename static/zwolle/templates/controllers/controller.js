/*
Controller for interface "$interfaceName$" (context: "$contextName$"). Generated code, edit with care.
$if(verbose)$Generated using template: $usedTemplate$
Generated by $ampersandVersionStr$

INTERFACE "$interfaceName$" : $expAdl$ :: $source$ * $target$ $if(exprIsUni)$[UNI]$endif$
Roles: [$roles;separator=", "$]
$endif$*/
/* jshint ignore:start */
angular.module('AmpersandApp').controller('Ifc$interfaceName$Controller', function (\$scope, \$rootScope, \$route, \$routeParams, \$sessionStorage, ResourceService) {
    const resourceType = '$source$';
    const ifcName = '$interfaceName$';
    let resource;
    
    // Set resourceId to special '_NEW' value in case new resource must be created
    if(\$routeParams['new'] && '$source$' == '$target$') 
        \$scope.resource = { _id_ : '_NEW', _path_ : 'resources/' + resourceType + '/_NEW', _isRoot_ : true };

    // Toplevel interface
    else if(resourceType == 'SESSION') 
        \$scope.resource = { _id_ : \$sessionStorage.session.id, _path_ : 'session', _isRoot_ : true };

    // Get requested resource
    else \$scope.resource = { _id_ : \$routeParams.resourceId, _path_ : 'resources/' + resourceType + '/' + \$routeParams.resourceId , _isRoot_ : true };
    
    \$scope.resource[ifcName] = $if(exprIsUni)$null$else$[]$endif$;
    \$scope.patchResource = \$scope.resource;
    
    \$scope.createResource = function(){ ResourceService.createResource(\$scope.resource, ifcName, \$scope.patchResource);};
    \$scope.resource.get = function(){ ResourceService.getResource(\$scope.resource, ifcName, \$scope.patchResource);};
    \$scope.saveResource = ResourceService.saveResource;
    \$scope.switchResource = function(resourceId){ \$location.url('/$interfaceName$/' + resourceId);};
    
    // Create new or get resource
    if(\$routeParams['new']) \$scope.createResource();
    else \$scope.resource.get();
    
});
/* jshint ignore:end */