/**
* @File Name : WrappersUtil.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : December 25, 2025
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | December 25, 2025 |   | Initial Version
**/

public class WrappersUtil {
	
	public class OpportunityContextWrapper {
		@AuraEnabled public Opportunity opportunity;
		@AuraEnabled public List<LineItemDTO> lineItems;
		@AuraEnabled public Integer dealHealthScore;

		public OpportunityContextWrapper() {
			lineItems = new List<LineItemDTO>();
		}
	}

	public class LineItemDTO {
		@AuraEnabled public Id Id;
		@AuraEnabled public Id productId;
		@AuraEnabled public String productName;
		@AuraEnabled public Decimal Quantity;
		@AuraEnabled public Decimal UnitPrice;
		@AuraEnabled public Decimal Discount;
		@AuraEnabled public Decimal effectivePrice;
		@AuraEnabled public Decimal externalUnitPrice;
		@AuraEnabled public Boolean isInStock;
		@AuraEnabled public Datetime externalLastChecked;
	}

	public class SimulationParams {
		@AuraEnabled public Decimal discountTier;
		@AuraEnabled public Decimal probability;

		public SimulationParams(
			Decimal discountTier,
			Decimal probability
		) {
			this.discountTier = discountTier;
			this.probability = probability;
		}
	}


	public class SimulationResult {
		@AuraEnabled public Decimal simulatedAmount;
		@AuraEnabled public Integer healthScore;
		@AuraEnabled public String recommendation;
	}

}