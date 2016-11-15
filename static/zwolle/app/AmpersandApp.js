// when using minified angular modules, use module('myApp', []).controller('MyController', ['myService', function (myService) { ...
angular.module('AmpersandApp', ['ngResource', 'ngRoute', 'ngSanitize', 'restangular', 'ui.bootstrap', 'uiSwitch', 'cgBusy', 'siTable', 'ng-code-mirror', 'ngStorage', 'angularFileUpload', 'agGrid', 'ui.bootstrap.datetimepicker', 'hc.marked'])
.config(function($routeProvider) {
    $routeProvider
        // default start page
        .when('/', { 
            controller : '',
            templateUrl : 'app/views/static_home.html',
            interfaceLabel : 'Home'
            })
        // installer page
        .when('/admin/installer', {
            controller : 'InstallerController',
            templateUrl : 'app/views/static_installer.html',
            interfaceLabel : 'Installer'
            })
        .when('/404', {
            templateUrl: 'app/views/static_404.html',
            interfaceLabel: '404'
            })
        .otherwise({redirectTo: '/404'});
}).config(function(RestangularProvider) {
    
    RestangularProvider.setBaseUrl('api/v1'); // Generate: path to API folder
    RestangularProvider.setDefaultHeaders({"Content-Type": "application/json"});
    // RestangularProvider.setPlainByDefault(true); available from Restangular v1.5.3
    
}).run(function(Restangular, $rootScope, $localStorage, $sessionStorage, $location, $route, NotificationService, RoleService){
    
    $sessionStorage.session = {'id' : initSessionId}; // initSessionId provided by index.php on startup application
        
    Restangular.addFullRequestInterceptor(function(element, operation, what, url, headers, params){
        params['roleIds[]'] = RoleService.getActiveRoleIds(); // the '[]' in param 'roleIds[]' is needed by the API to process it as array
        params.navIfc = true;
        params.metaData = true;
        return params;
    });
    
    Restangular.addResponseInterceptor(function(data, operation, what, url, response, deferred){
        if(operation != 'get' && operation != 'getList' && data.sessionRefreshAdvice) $rootScope.refreshNavBar();
        
        return data;
    });
    
    Restangular.setErrorInterceptor(function(response, deferred, responseHandler) {
        
        // 401: Unauthorized, 440: Login Timeout
        if(response.status == 401 || response.status == 440) {
            RoleService.deactivateAllRoles();
            $location.path(''); // TODO: redirect to login page (if exists)
        }
        
        var message;
        var details;
        if(typeof response.data === 'object'){
            message = response.data.msg || response.statusText; // if empty response message, take statusText
            NotificationService.addError(message, response.status, true);
            
            if(response.data.notifications !== undefined) NotificationService.updateNotifications(response.data.notifications); 
        }else{
            message = response.status + ' ' + response.statusText;
            details = response.data; // html content is excepted
            NotificationService.addError(message, response.status, true, details);
        }
        
        return true; // proceed with success or error hooks of promise
    });
    
    $rootScope.getCurrentDateTime = function (){
        return new Date();
    };
    
    // Add feature to $location.url() function to be able to prevent reloading page (set reload param to false)
    var original = $location.url;
    $location.url = function (url, reload) {
        if (reload === false) {
            var lastRoute = $route.current;
            var un = $rootScope.$on('$locationChangeSuccess', function () {
                $route.current = lastRoute;
                un();
            });
        }
        return original.apply($location, [url]);
    };
    
    
}).value('cgBusyDefaults',{
    message:'Loading...',
    backdrop: true,
    //templateUrl: 'my_custom_template.html',
    //delay: 500, // in ms
    minDuration: 500, // in ms
    // wrapperClass: 'my-class my-class2'
}).directive('myShowonhoverBox', function (){
    return {
        link : function(scope, element, attrs) {
            if(!element.closest('.box').hasClass('my-showonhover-box-show')) element.hide(); // default hide
            
            element.closest('.box').bind('mouseenter', function() {
                element.closest('.box').addClass('my-showonhover-box-show');
                element.show();
            });
            element.closest('.box').bind('mouseleave', function() {
                element.closest('.box').removeClass('my-showonhover-box-show');
                element.hide();
            });
        }
    };
}).directive('myBluronenter', function() {
    return function(scope, element, attrs) {
        element.bind("keydown keypress", function(event) {
            if(event.which === 13) { // 13 = Carriage return
                event.target.blur();

                event.preventDefault();
            }
        });
    };
}).filter('toArray', function() {
    // used from: https://github.com/petebacondarwin/angular-toArrayFilter
    return function (obj, addKey) {
        if (!obj) return obj;
        if ($.isArray(obj)) return obj; // obj is already an array
        if ( addKey === false ) {
          return Object.keys(obj).map(function(key) {
            return obj[key];
          });
        } else {
          return Object.keys(obj).map(function (key) {
            return Object.defineProperty(obj[key], '$key', { enumerable: false, value: key});
          });
        }
      };
}).directive('myNavToInterfaces', function(){
    return {
        restrict : 'E',
        scope : {ifcs : '=', resource : '=', target : '@'}, // '=' => two-way bind, '@' => evaluates string (use {{}} in html) 
        templateUrl : 'app/views/partials/my_nav_to_interfaces.html',
        transclude : true
    };
}).directive('myNavToOtherInterfaces', function(){
    return {
        restrict : 'E',
        scope  : {ifcs : '=', resource : '=', label : '=', target : '@'}, // '=' => two-way bind, '@' => evaluates string (use {{}} in html) 
        templateUrl : 'app/views/partials/my_nav_to_other_interfaces.html'
    };
}).directive('myAlias', function($animate, $compile) {
    // adapted from ngIf and ngRepeat directives
    // use e.g.: <div my-alias="resource['Project'] as test">{{test}}</div>
    return {
        transclude: 'element',
        priority: 600, // like ngIf directive
        terminal: true,
        restrict: 'A',
        // scope: true,
        link: function($scope, $element, $attr, ctrl, $transclude) {
            var block, childScope, previousElements;
            
            var expression = $attr.myAlias;
            var args = expression.split(' as ');
            if(!args[1]) throw "No 'as' specified for my-alias directive";
            
            var lhs = args[0];
            var rhs = args[1];
            
            $scope.$watch(lhs, function(value) {
                if (value) {
                    if (!childScope) {
                        $transclude(function(clone, newScope) {
                            childScope = newScope;
                            
                            // Create alias in new childScope
                            childScope[rhs] = $scope.$eval(lhs);
                            
                            clone[clone.length++] = document.createComment(' end myAlias: ' + $attr.myAlias + ' ');
                            // Note: We only need the first/last node of the cloned nodes.
                            // However, we need to keep the reference to the jqlite wrapper as it might be changed later
                            // by a directive with templateUrl when its template arrives.
                            block = {
                                clone: clone
                            };
                            $animate.enter(clone, $element.parent(), $element);
                        });
                    }
                } else {
                    if (previousElements) {
                        previousElements.remove();
                        previousElements = null;
                    }
                    if (childScope) {
                        childScope.$destroy();
                        childScope = null;
                    }
                    if (block) {
                        previousElements = getBlockNodes(block.clone);
                        $animate.leave(previousElements).then(function() {
                            previousElements = null;
                        });
                        block = null;
                    }
                }
            });
        }
    };
}).filter('unsafe', function($sce){
    return $sce.trustAsHtml;
});