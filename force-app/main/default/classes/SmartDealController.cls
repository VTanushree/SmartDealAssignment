public with sharing class SmartDealController {

    // Wrapper class used for deserialization
    public class ProductRow {
        @AuraEnabled public String productId {get;set;}
        @AuraEnabled public Decimal quantity {get;set;}
        @AuraEnabled public Decimal unitPrice {get;set;}
        @AuraEnabled public Decimal discount {get;set;}
        @AuraEnabled public Decimal externalPrice {get;set;}
        @AuraEnabled public Boolean inStock {get;set;}
    }    
    
    @AuraEnabled
    public static void saveLineItems(Id oppId, String rowData) { // [UPDATED] Parameter is now String
        try {
            // [NEW LINE] Convert the JSON string back into a List of our Wrapper class
            List<ProductRow> deserializedRows = (List<ProductRow>)JSON.deserialize(rowData, List<ProductRow>.class);
            
            System.debug('oppId::' + oppId);
            System.debug('deserializedRows::' + deserializedRows);

            Opportunity opp = [SELECT Pricebook2Id FROM Opportunity WHERE Id = :oppId LIMIT 1];
            Id pricebookId = opp.Pricebook2Id;

            if (pricebookId == null) {
                throw new AuraHandledException('Please select a Pricebook on the Opportunity before adding products.');
            }

            // [UPDATED] Using the new deserializedRows list
            Set<Id> productIds = new Set<Id>();
            for (ProductRow row : deserializedRows) {
                if (String.isNotBlank(row.productId)) {
                    productIds.add((Id)row.productId);
                }
            }

            Map<Id, Id> productToPbeMap = new Map<Id, Id>();
            for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry 
                                       WHERE Pricebook2Id = :pricebookId 
                                       AND Product2Id IN :productIds 
                                       AND IsActive = true]) {
                productToPbeMap.put(pbe.Product2Id, pbe.Id);
            }

            List<OpportunityLineItem> olisToInsert = new List<OpportunityLineItem>();
            for (ProductRow row : deserializedRows) {
                if (productToPbeMap.containsKey(row.productId)) {
                    OpportunityLineItem oli = new OpportunityLineItem();
                    oli.OpportunityId = oppId;
                    oli.PricebookEntryId = productToPbeMap.get(row.productId);
                    oli.Quantity = row.quantity;
                    oli.UnitPrice = row.unitPrice;
                    oli.Discount = row.discount;
                    olisToInsert.add(oli);
                }
            }

            if (!olisToInsert.isEmpty()) {
                insert olisToInsert;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
 

    @AuraEnabled(cacheable=true)
    public static WrappersUtil.OpportunityContextWrapper getOpportunityContext(Id oppId) {
        // [EXISTING LOGIC - UNCHANGED]
        Opportunity opp = [
            SELECT Id, Name, StageName, CloseDate, Amount,
                   AccountId, Deal_Health_Score__c
            FROM Opportunity
            WHERE Id = :oppId
        ];

        List<OpportunityLineItem> olis = [
            SELECT Id, Quantity, UnitPrice, Discount,
                   PricebookEntry.Product2Id,
                   PricebookEntry.Product2.Name,
                   External_Unit_Price__c,
                   Is_In_External_Stock__c,
                   External_Price_Last_Checked__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :oppId
        ];

        WrappersUtil.OpportunityContextWrapper ctx = new WrappersUtil.OpportunityContextWrapper();
        ctx.opportunity = opp;
        ctx.dealHealthScore = (Integer) opp.Deal_Health_Score__c;

        for (OpportunityLineItem oli : olis) {
            WrappersUtil.LineItemDTO dto = new WrappersUtil.LineItemDTO();
            dto.Id = oli.Id;
            dto.productId = oli.PricebookEntry.Product2Id;
            dto.productName = oli.PricebookEntry.Product2.Name;
            dto.Quantity = oli.Quantity;
            dto.UnitPrice = oli.UnitPrice;
            dto.Discount = oli.Discount;
            dto.externalUnitPrice = oli.External_Unit_Price__c;
            dto.isInStock = oli.Is_In_External_Stock__c;
            dto.externalLastChecked = oli.External_Price_Last_Checked__c;

            ctx.lineItems.add(dto);
        }

        return ctx;
    }

    @AuraEnabled
    public static Integer recalculateDealHealth(Id oppId) {
        // [EXISTING LOGIC - UNCHANGED]
        Opportunity opp = [
            SELECT Amount, Probability
            FROM Opportunity
            WHERE Id = :oppId 
        ];

        Integer score = 0;
        score += Integer.valueOf(opp.Probability * 0.6);
        score += opp.Amount > 50000 ? 40 : 20;
        score = Math.min(100, score);
        opp.Deal_Health_Score__c =  score;
        
        if (opp != null && Schema.sObjectType.Opportunity.isUpdateable()) {
            update opp;
        }
        return score;
    }

    @AuraEnabled(cacheable=true)
    public static List<SObject> getRelatedRecords(
        String parentId, 
        String objectName, 
        Integer rowLimit, 
        Integer rowOffset
    ) {
        String query = 'SELECT Id ';
        String whereClause = '';
        // Get the AccountId from the Opportunity
        Id accId = [SELECT AccountId FROM Opportunity WHERE Id = :parentId LIMIT 1].AccountId;
        
        if (objectName == 'Contact') {
            query += ', Name, Email FROM Contact ';
            whereClause = ' WHERE AccountId = :accId';
        } else if (objectName == 'Case') {
            query += ', Subject, Status FROM Case';
            // Filter: Only Open Cases related to Account
            whereClause = ' WHERE IsClosed = false AND AccountId = :accId';
        } else if (objectName == 'Installation__c') {
            query += ', Status__c FROM Installation__c';
            // Filter: Only Active Installations related to Opportunity
            whereClause = ' WHERE Status__c != \'Cancelled\' AND Opportunity__c = :parentId';
        }

        query += whereClause + ' ORDER BY CreatedDate DESC LIMIT :rowLimit OFFSET :rowOffset';
        return Database.query(query);
    }
    
    @AuraEnabled
    public static void refreshExternalPricing(Id oppId) {
        ExternalPricingService.refreshPricing(oppId);
    }
}