@IsTest
public class SmartDealControllerTest {

    /* ------------------------------------------------------------
     * TEST DATA SETUP
     * ---------------------------------------------------------- */
    /**
     * @testSetup method to insert all base data once for all tests:
     * - Account, Contact, Standard Pricebook, Product, PricebookEntry, 
     *   Opportunity, OpportunityLineItem, Installation__c, Case.
     * This ensures each test runs faster and with consistent data.
     */
    @testSetup
    static void setupData() {
        // Create an Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create a Contact related to the Account
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'test@example.com',
            AccountId = acc.Id
        );
        insert con;

        // Get Standard Pricebook (required for product pricing)
        Id stdPb = Test.getStandardPricebookId();

        // Create an active Product
        Product2 prod = new Product2(
            Name = 'Solar Panel',
            IsActive = true
        );
        insert prod;

        // Add a PricebookEntry for the Product in the Standard Pricebook (required for OLI)
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = prod.Id,
            Pricebook2Id = stdPb,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe;

        // Create an Opportunity using this Pricebook
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 60000,
            Probability = 70,
            AccountId = acc.Id,
            Pricebook2Id = stdPb
        );
        insert opp;

        // Insert an existing OpportunityLineItem for the Opportunity
        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 1000,
            Discount = 10
        );
        insert oli;

        // Insert an Installation__c (for testing related record retrieval)
        Installation__c inst = new Installation__c(
            Opportunity__c = opp.Id,
            Status__c = 'Planned'
        );
        insert inst;

        // Insert a Case record related to the Account
        Case c = new Case(
            Subject = 'Test Case',
            Status = 'New',
            AccountId = acc.Id
        );
        insert c;
    }

    /* ------------------------------------------------------------
     * TEST: saveLineItems
     * ---------------------------------------------------------- */
    /**
     * Test that a new OpportunityLineItem can be successfully inserted using saveLineItems,
     * and that the total count of OLIs increases as expected.
     */
    @IsTest
    static void testSaveLineItems_success() {
        // Query test Opportunity and Product
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 LIMIT 1];

        // Create a new ProductRow wrapper to represent a line item
        List<SmartDealController.ProductRow> rows = new List<SmartDealController.ProductRow>();
        SmartDealController.ProductRow row = new SmartDealController.ProductRow();
        row.productId = prod.Id;
        row.quantity = 3;
        row.unitPrice = 1200;
        row.discount = 5;
        rows.add(row);

        // Serialize ProductRow to JSON for method input
        String jsonRows = JSON.serialize(rows);

        // Call method under test
        Test.startTest();
        SmartDealController.saveLineItems(opp.Id, jsonRows);
        Test.stopTest();

        // Query OLIs and assert expected count (existing + new)
        List<OpportunityLineItem> olis = [
            SELECT Quantity, UnitPrice, Discount
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
        ];
        System.assertEquals(2, olis.size(), 'New OLI should be inserted');
    }

    /* ------------------------------------------------------------
     * TEST: getOpportunityContext
     * ---------------------------------------------------------- */
    /**
     * Test that getOpportunityContext returns a non-null wrapper
     * and that for the test Opportunity, line items are included.
     */
    @IsTest
    static void testGetOpportunityContext() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        WrappersUtil.OpportunityContextWrapper ctx =
            SmartDealController.getOpportunityContext(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, ctx, 'OpportunityContextWrapper should not be null');
        System.assertEquals(opp.Id, ctx.opportunity.Id, 'Opportunity Id should match input');
        System.assert(ctx.lineItems.size() > 0, 'Line items should be returned');
    }

    /* ------------------------------------------------------------
     * TEST: recalculateDealHealth
     * ---------------------------------------------------------- */
    /**
     * Test that recalculateDealHealth updates the Opportunity's Deal_Health_Score__c
     * and caps the score at 100 or below.
     */
    @IsTest
    static void testRecalculateDealHealth() {
        Opportunity opp = [
            SELECT Id, Deal_Health_Score__c
            FROM Opportunity LIMIT 1
        ];

        Test.startTest();
        Integer score = SmartDealController.recalculateDealHealth(opp.Id);
        Test.stopTest();

        // Query updated Opportunity to check the new field value
        Opportunity updatedOpp = [
            SELECT Deal_Health_Score__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assert(score <= 100, 'Score must be capped at 100');
        System.assertEquals(
            updatedOpp.Deal_Health_Score__c,
            score,
            'Deal Health Score should be updated'
        );
    }

    /* ------------------------------------------------------------
     * TEST: getRelatedRecords - Contact
     * ---------------------------------------------------------- */
    /**
     * Test that getRelatedRecords returns Contact records linked to the opportunity's Account.
     */
    @IsTest
    static void testGetRelatedRecords_contact() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<SObject> records =
            SmartDealController.getRelatedRecords(
                opp.Id,
                'Contact',
                10,
                0
            );
        Test.stopTest();

        System.assert(records.size() > 0, 'Contacts should be returned');
    }

    /* ------------------------------------------------------------
     * TEST: getRelatedRecords - Installation__c
     * ---------------------------------------------------------- */
    /**
     * Test that getRelatedRecords returns Installation__c records for the given opportunity.
     */
    @IsTest
    static void testGetRelatedRecords_installation() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<SObject> records =
            SmartDealController.getRelatedRecords(
                opp.Id,
                'Installation__c',
                10,
                0
            );
        Test.stopTest();

        System.assert(records.size() > 0, 'Installations should be returned');
    }

    /* ------------------------------------------------------------
     * TEST: refreshExternalPricing (CALL OUT)
     * ---------------------------------------------------------- */
    /**
     * Test that refreshExternalPricing executes an external pricing callout without exception,
     * using a mock class for the callout.
     */
    @IsTest
    static void testRefreshExternalPricing() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Register mock implementation for HTTP callout
        Test.setMock(
            HttpCalloutMock.class,
            new ExternalPricingServiceMock()
        );

        Test.startTest();
        SmartDealController.refreshExternalPricing(opp.Id);
        Test.stopTest();

        // If no exception, the test passes
        System.assert(true, 'External pricing callout executed');
    }

    /* ------------------------------------------------------------
     * HTTP CALLOUT MOCK
     * ---------------------------------------------------------- */
    /**
     * Mock response for ExternalPricingService.refreshPricing HTTP callout method.
     * This prevents real callouts from happening during testing and returns a valid fake response.
     */
    private class ExternalPricingServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '[{"productId":"01t000000000001","unitPrice":1500,"inStock":true}]'
            );
            return res;
        }
    }
}