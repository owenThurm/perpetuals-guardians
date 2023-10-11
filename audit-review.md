## Notes:

1. 

> No minimumPositionSize for opening a position, so if not provided other functions get affected for unnecceasrily lower balance fees count

A minimum position size may be useful to prevent potential gaming, however the finding does not point to any particular scenario that would merit a high severity or a description of how other functions would be affected.

Result: Readjust to `Low`

2. 

> In increasePositionSize function, the borrowing fees has applied on a original position
.it should be applied on a new position, after the positionFee is being applied. Also, it should be applied after checking the healthFactor.
this may lead to the leverage ratio being higher than intended (this may result in liquidation) 

The finding indicates that the borrowing fee should be charged after the positionFee and after validating the health factor, however this is not true. If the borrowing fee were applied before validating the health factor then a position that doesn't meet the health factor can pass execution of the increasePositionSize function.

Result: `Invalid`


3.  

> In liquidate function: No insufficient collateral-condition-check before reducing borrowing fees from collateral
(i.e. what if position.collaateral < borrwingfees). also after calculating pnl

This is indeed an unaddressed edge case which can have nasty consequences (unliquidatable position as the liqudiate function reverts).

Result: `Valid`


4. 

>  In liquidate function: No insufficient collateral-condition-check before reducing liquidation fees from collateral
(i.e. what if position.collateral < liquidationfees). Liquidators will not be incentivized to liquidate those accounts that do not
provide them with a liquidation fee. As a result, the liquidation of these accounts might be delayed or not performed at all.

Similar to 3, this is an unaddressed edge case.

Result: `Valid`

5. 

> No position health check in increasePositionSize function beofre applying borrowing and position fees,
leading a miscalculation which eventually affects the liquidation conditions.

The health check should be performed after the position is updated, that way the position is left in a non-liquidatable state after it's size is updated.

Result: `Invalid`


6. 

> BorrowingFee applied in function increaseCollateral. No need.

It is fine and perhaps perferrable to apply the borrowing fees every time a position is updated, including increasePositionCollateral updates.

Result: `Invalid`


7. 

> In decreasePosition function, borrowingFee has been deducted without considering the PnL || positionHealth of the given state of UserPosition.

Borrowing fees do not need to consider the PnL and the position health will be validated at the end of the function after all updates have been made to the position.

Result: `Invalid`

8. 

> In function isLiquidatable, positionCollateral value can be <= 0, No non-zero && non-negative checks are provided
before calculating leverage. Hence leaving many positions unliquidatable.

This finding is in the area of an important issue, however does not clearly illustrate it. When the positionPnL is negative and has a greater magnitude than the collateral, the following calculation on line 388 will silently overflow and leave the positionCollateral as a value near the maximum uint256:

`positionCollateral = (positionCollateral.toInt256() + positionPnL).toUint256();`

Result: `Valid`

9. 

> In function increasePositionCollateral, positionHealth check is not done before adding the collateral amount.

The position health check should be performed after all updates so that a position cannot be left in an unhealthy state.

Result: `Invalid`



10. 

> no withdrawCollateral function

Collateral may be withdrawn with the `decreasePosition` function.

Result: `Invalid`


11. 

> no closePosition function

A position may be closed with the `decreasePosition` function.

Result: `Invalid`


12. 

> no deposit collateral

Collateral may be deposited with the `openPosition` and `increasePositionCollateral` functions.

Result: `Invalid`


13. 

> Functions mint, withdraw , redeem were not implemented completely so it's always gonna revert

These functions were overriden on purpose so that only the `addLiquidity` and `removeLiquidity` functions can be used.

Result: `Invalid`


