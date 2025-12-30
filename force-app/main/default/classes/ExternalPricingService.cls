public with sharing class ExternalPricingService {

    public class PricingResponse {
        public String productId;
        public Decimal unitPrice;
        public Boolean inStock;
    }

    public class ExternalPricingException extends Exception {}

    public static void refreshPricing(Id oppId) {

        // 1. Get OLIs
        List<OpportunityLineItem> olis = [
            SELECT Id, PricebookEntry.Product2Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :oppId
        ];

        if (olis.isEmpty()) return;

        List<String> productIds = new List<String>();
        for (OpportunityLineItem oli : olis) {
            productIds.add((String)oli.PricebookEntry.Product2Id);
        }

        // 2. Build request
        External_API_Config__mdt cfg =
            External_API_Config__mdt.getInstance('Default');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Base_URL__c);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');

        req.setBody(JSON.serialize(new Map<String, Object>{
            'opportunityId' => oppId,
            'productIds' => productIds
        }));

        // 3. Callout
        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new ExternalPricingException('Pricing API failed');
        }

        // 4. Parse response
        List<PricingResponse> pricing =
            (List<PricingResponse>) JSON.deserialize(
                res.getBody(),
                List<PricingResponse>.class
            );

        Map<Id, PricingResponse> pricingMap = new Map<Id, PricingResponse>();
        for (PricingResponse pr : pricing) {
            pricingMap.put((Id) pr.productId, pr);
        }

        // 5. Update OLIs
        List<OpportunityLineItem> updates = new List<OpportunityLineItem>();
        for (OpportunityLineItem oli : olis) {
            PricingResponse pr = pricingMap.get(oli.PricebookEntry.Product2Id);
            if (pr != null) {
                oli.External_Unit_Price__c = pr.unitPrice;
                oli.Is_In_External_Stock__c = pr.inStock;
                oli.External_Price_Last_Checked__c = System.now();
                updates.add(oli);
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }

        // 6. Update Opportunity timestamp
        update new Opportunity(
            Id = oppId,
            External_Pricing_Last_Run__c = System.now()
        );
    }
}