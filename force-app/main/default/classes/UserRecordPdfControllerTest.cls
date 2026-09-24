@isTest
private class UserRecordPdfControllerTest {

    @testSetup
    static void setupTestData() {
        // Create test Account
        Account acc = new Account(
            Name = 'Acme Test Corp',
            Type = 'Customer - Direct',
            Industry = 'Technology',
            Phone = '555-0199',
            BillingCity = 'San Francisco',
            BillingCountry = 'United States',
            BillingState = 'California',
            AnnualRevenue = 5000000
        );
        insert acc;

        // Create test Contact
        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = acc.Id,
            Title = 'Chief Technology Officer',
            Email = 'johndoe@acmetest.com',
            Phone = '555-0123',
            Department = 'Engineering'
        );
        insert con;

        // Create test Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Acme Cloud Transformation',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 120000,
            Probability = 20
        );
        insert opp;

        // Create test Lead
        Lead ld = new Lead(
            FirstName = 'Jane',
            LastName = 'Smith',
            Company = 'Future Innovators LLC',
            Title = 'Product VP',
            Email = 'jane@futureinnovators.com',
            Phone = '555-0987',
            Status = 'Open - Not Contacted',
            LeadSource = 'Web'
        );
        insert ld;
    }

    @isTest
    static void testGetLoggedInUserInfo() {
        Test.startTest();
        UserRecordPdfController.UserInfoWrapper info = UserRecordPdfController.getLoggedInUserInfo();
        Test.stopTest();

        Assert.isNotNull(info, 'User info wrapper should not be null');
        Assert.areEqual(UserInfo.getUserId(), info.userId, 'User ID should match logged-in user');
        Assert.isNotNull(info.name, 'User name should not be blank');
    }

    @isTest
    static void testGetAllAccessibleObjects() {
        Test.startTest();
        List<UserRecordPdfController.ObjectOption> objs = UserRecordPdfController.getAllAccessibleObjects();
        Test.stopTest();

        Assert.isNotNull(objs, 'Object list should not be null');
        Assert.isTrue(objs.size() > 0, 'Should return accessible objects');
    }

    @isTest
    static void testGetObjectFields() {
        Test.startTest();
        List<UserRecordPdfController.FieldOption> fields = UserRecordPdfController.getObjectFields('Account');
        Test.stopTest();

        Assert.isNotNull(fields, 'Fields list should not be null');
        Assert.isTrue(fields.size() > 0, 'Account should have accessible fields');
    }

    @isTest
    static void testGetDynamicObjectRecords() {
        Test.startTest();
        List<String> selectedCols = new List<String>{'Name', 'Industry', 'Phone', 'AnnualRevenue'};
        UserRecordPdfController.DynamicTableResponse res = UserRecordPdfController.getDynamicObjectRecords(
            'Account', 
            selectedCols, 
            false, 
            'Acme'
        );
        Test.stopTest();

        Assert.isNotNull(res, 'Response should not be null');
        Assert.areEqual('Account', res.objectApiName);
        Assert.areEqual(1, res.records.size(), 'Should find 1 test account matching Acme');
        Assert.areEqual(4, res.columns.size(), 'Should contain 4 requested columns');
    }

    @isTest
    static void testGetDynamicRecordsDefaultFields() {
        Test.startTest();
        UserRecordPdfController.DynamicTableResponse res = UserRecordPdfController.getDynamicObjectRecords(
            'Contact', 
            new List<String>(), 
            false, 
            ''
        );
        Test.stopTest();

        Assert.isNotNull(res, 'Response should not be null');
        Assert.isTrue(res.records.size() > 0, 'Should return test contacts');
        Assert.isTrue(res.columns.size() > 0, 'Should populate default columns');
    }

    @isTest
    static void testInvalidObjectException() {
        Test.startTest();
        try {
            UserRecordPdfController.getDynamicObjectRecords('NonExistentObject__c', new List<String>(), false, '');
            Assert.fail('Expected exception was not thrown');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage());
        }
        Test.stopTest();
    }
}
