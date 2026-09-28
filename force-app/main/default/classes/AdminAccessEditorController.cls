/**
 * @description LWC controller for the Profile / User access editor (adminAccessEditor).
 * All reads are non-cacheable so the editor always shows current access after a save.
 */
public with sharing class AdminAccessEditorController {

    @AuraEnabled
    public static AdminSecurityDataModel.AccessContext getAccessContext(String targetType, Id targetId) {
        try {
            return AdminAccessEditorService.getAccessContext(targetType, targetId);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static List<AdminSecurityDataModel.AssignmentItem> getAssignments(String targetType, Id targetId, String kind) {
        try {
            return AdminAccessEditorService.getAssignments(targetType, targetId, kind);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult setAssignment(String targetType, Id targetId, String kind, Id itemId, Boolean assign) {
        try {
            return AdminAccessEditorService.setAssignment(targetType, targetId, kind, itemId, assign);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static List<AdminSecurityDataModel.EntityAccessItem> getEntityAccess(String targetType, Id targetId, String entityType) {
        try {
            return AdminAccessEditorService.getEntityAccess(targetType, targetId, entityType);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult saveEntityAccess(String targetType, Id targetId, String entityType, String changesJson) {
        try {
            return AdminAccessEditorService.saveEntityAccess(targetType, targetId, entityType, changesJson);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static List<AdminSecurityDataModel.ObjectAccessItem> getObjectAccess(String targetType, Id targetId) {
        try {
            return AdminAccessEditorService.getObjectAccess(targetType, targetId);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult saveObjectAccess(String targetType, Id targetId, String changesJson) {
        try {
            return AdminAccessEditorService.saveObjectAccess(targetType, targetId, changesJson);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static List<AdminSecurityDataModel.FieldAccessItem> getFieldAccess(String targetType, Id targetId, String sobjectType) {
        try {
            return AdminAccessEditorService.getFieldAccess(targetType, targetId, sobjectType);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult saveFieldAccess(String targetType, Id targetId, String sobjectType, String changesJson) {
        try {
            return AdminAccessEditorService.saveFieldAccess(targetType, targetId, sobjectType, changesJson);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static List<AdminSecurityDataModel.RecordTypeItem> getRecordTypes() {
        try {
            return AdminAccessEditorService.getRecordTypes();
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    @AuraEnabled
    public static AdminSecurityDataModel.DmlResult changeUserProfile(Id userId, Id profileId) {
        try {
            return AdminAccessEditorService.changeUserProfile(userId, profileId);
        } catch (Exception ex) {
            throw toAuraException(ex);
        }
    }

    private static AuraHandledException toAuraException(Exception ex) {
        if (ex instanceof AuraHandledException) {
            return (AuraHandledException) ex;
        }
        String message = ex instanceof DmlException ? ex.getDmlMessage(0) : ex.getMessage();
        AuraHandledException aura = new AuraHandledException(message);
        aura.setMessage(message);
        return aura;
    }
}
