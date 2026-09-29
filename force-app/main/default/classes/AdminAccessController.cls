/**
 * @description Lightning Web Component Controller facade for Admin Access Console.
 * Enforces user mode, admin authorization, and handles error messaging.
 */
public with sharing class AdminAccessController {

    @AuraEnabled(cacheable=true)
    public static AdminSecurityDataModel.AdminSecurityOverview getAdminOverview() {
        try {
            return AdminSecurityService.getAdminOverview();
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.AdminUserInfo> getUsers(String searchTerm, String profileId, String statusFilter) {
        try {
            return AdminSecurityService.getUsers(searchTerm, profileId, statusFilter);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static AdminSecurityDataModel.UserDetailView getUserDetail(Id userId) {
        try {
            return AdminSecurityService.getUserDetail(userId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.PermissionSetSummary> getPermissionSets(String searchTerm, String typeFilter) {
        try {
            return AdminSecurityService.getPermissionSets(searchTerm, typeFilter);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static AdminSecurityDataModel.PermissionSetDetail getPermissionSetDetail(Id permissionSetId) {
        try {
            return AdminSecurityService.getPermissionSetDetail(permissionSetId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.PermissionSetGroupSummary> getPermissionSetGroups(String searchTerm, String statusFilter) {
        try {
            return AdminSecurityService.getPermissionSetGroups(searchTerm, statusFilter);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static AdminSecurityDataModel.PermissionSetGroupDetail getPermissionSetGroupDetail(Id groupId) {
        try {
            return AdminSecurityService.getPermissionSetGroupDetail(groupId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.ProfileSummary> getProfiles(String searchTerm, String licenseFilter) {
        try {
            return AdminSecurityService.getProfiles(searchTerm, licenseFilter);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static AdminSecurityDataModel.ProfileDetail getProfileDetail(Id profileId) {
        try {
            return AdminSecurityService.getProfileDetail(profileId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<AdminSecurityDataModel.ObjectPermItem> getObjectPermissionsForTarget(Id parentId, String targetType, String searchTerm) {
        try {
            return AdminSecurityService.getObjectPermissionsForTarget(parentId, targetType, searchTerm);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<AdminSecurityDataModel.FieldPermItem> getFieldPermissionsForTarget(Id parentId, String targetType, String sobjectType, String searchTerm) {
        try {
            return AdminSecurityService.getFieldPermissionsForTarget(parentId, targetType, sobjectType, searchTerm);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.AppAccessSummary> getAppAccessList(String searchTerm) {
        try {
            return AdminSecurityService.getAppAccessList(searchTerm);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AdminSecurityDataModel.SelectOption> getAccessibleObjects() {
        try {
            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
            List<AdminSecurityDataModel.SelectOption> options = new List<AdminSecurityDataModel.SelectOption>();

            Set<String> commonObjects = new Set<String>{
                'account', 'contact', 'opportunity', 'lead', 'case', 'campaign',
                'order', 'contract', 'product2', 'pricebook2', 'asset', 'task', 'event', 'user'
            };

            for (String key : gd.keySet()) {
                String lowerKey = key.toLowerCase();
                if (lowerKey.endsWith('__share') || lowerKey.endsWith('__history') || lowerKey.endsWith('__feed')) {
                    continue;
                }
                Boolean isCustom = lowerKey.endsWith('__c');
                Boolean isCommon = commonObjects.contains(lowerKey);

                if (isCustom || isCommon) {
                    Schema.DescribeSObjectResult descr = gd.get(key).getDescribe();
                    if (descr.isAccessible() && descr.isQueryable() && !descr.isCustomSetting()) {
                        options.add(new AdminSecurityDataModel.SelectOption(descr.getLabel() + ' (' + descr.getName() + ')', descr.getName(), isCustom ? 'Custom' : 'Standard'));
                    }
                }
            }
            options.sort();
            return options;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // =========================================================================
    // MUTATION ENDPOINTS (DML)
    // =========================================================================

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult assignPermissionSetToUser(Id userId, Id permissionSetId) {
        try {
            return AdminSecurityService.assignPermissionSetToUser(userId, permissionSetId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult removePermissionSetFromUser(Id userId, Id permissionSetId) {
        try {
            return AdminSecurityService.removePermissionSetFromUser(userId, permissionSetId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult assignPermissionSetGroupToUser(Id userId, Id permissionSetGroupId) {
        try {
            return AdminSecurityService.assignPermissionSetGroupToUser(userId, permissionSetGroupId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult removePermissionSetGroupFromUser(Id userId, Id permissionSetGroupId) {
        try {
            return AdminSecurityService.removePermissionSetGroupFromUser(userId, permissionSetGroupId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult assignUsersToPermissionSet(Id permissionSetId, List<Id> userIds) {
        try {
            return AdminSecurityService.assignUsersToPermissionSet(permissionSetId, userIds);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult removeUsersFromPermissionSet(Id permissionSetId, List<Id> userIds) {
        try {
            return AdminSecurityService.removeUsersFromPermissionSet(permissionSetId, userIds);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult assignUsersToPermissionSetGroup(Id permissionSetGroupId, List<Id> userIds) {
        try {
            return AdminSecurityService.assignUsersToPermissionSetGroup(permissionSetGroupId, userIds);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult removeUsersFromPermissionSetGroup(Id permissionSetGroupId, List<Id> userIds) {
        try {
            return AdminSecurityService.removeUsersFromPermissionSetGroup(permissionSetGroupId, userIds);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult saveObjectPermissions(
        Id permissionSetId,
        String sobjectType,
        Boolean canRead,
        Boolean canCreate,
        Boolean canEdit,
        Boolean canDelete,
        Boolean canViewAll,
        Boolean canModifyAll
    ) {
        try {
            return AdminSecurityService.saveObjectPermissions(
                permissionSetId, sobjectType, canRead, canCreate, canEdit, canDelete, canViewAll, canModifyAll
            );
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult saveFieldPermissions(
        Id permissionSetId,
        String sobjectType,
        String fieldApiName,
        Boolean canRead,
        Boolean canEdit
    ) {
        try {
            return AdminSecurityService.saveFieldPermissions(
                permissionSetId, sobjectType, fieldApiName, canRead, canEdit
            );
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult toggleUserActiveStatus(Id userId, Boolean isActive) {
        try {
            return AdminSecurityService.toggleUserActiveStatus(userId, isActive);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult createPermissionSetGroup(String masterLabel, String developerName, String description) {
        try {
            return AdminSecurityService.createPermissionSetGroup(masterLabel, developerName, description);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult addPermissionSetsToGroup(Id groupId, List<Id> permissionSetIds) {
        try {
            return AdminSecurityService.addPermissionSetsToGroup(groupId, permissionSetIds);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult removePermissionSetFromGroup(Id groupId, Id permissionSetId) {
        try {
            return AdminSecurityService.removePermissionSetFromGroup(groupId, permissionSetId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult createUser(String firstName, String lastName, String email, String username, String alias, Id profileId) {
        try {
            return AdminSecurityService.createUser(firstName, lastName, email, username, alias, profileId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
