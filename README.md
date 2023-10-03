# How does the system work? How would a user interact with it?

Our Perpetual Protocol supports both long and short positions. DAI is required as collateral, and we offer the option to trade with ETH.
For example:

- ETH/USD market with both long and short collateral tokens as DAI, and the index token as ETH.

Liquidity providers can deposit DAI.
Liquidity providers bear the profits and losses of traders in the market for which they provide liquidity.

## How users interract with it

Traders can use

- `openPosition` to open a position. Traders can only open one position at a time. The function accepts `size` and `collateral`in DAI as well as a boolean to indicate if the position is long or short. We accept only one position per trader.
- `increasePositionSize` to increase a position's size. The function accepts `size` in DAI, and will be converted to the it's current `ETH` value, in order to be added to the position.
- `increasePositionCollateral` to increase collateral. Raw amount of `DAI` is taken.
- `decreasePosition` to decrease size and collateral. Accepts `DAI` for both size and collateral. Calculates partial PnL. If the PnL is positive, it distributes it to the trader. If the PnL is negative, it trasfers it to the liquidity pool.

Liquidity providers can use

- `addLiquidity` to add liquidity
- `removeLiquidity` to remove liquidity

Liquidators can use

- `isLiquidatable` to check if a trader's position could be liquidated. We account for all fees and PnL before calculating the leverage.
- `liquidate` to liquidate a trader's position. PnL goes to LPs, Fees go to LPs, 10% of the remaining collateral goes to the liquidator and all the rest is sent back to the trader.

Owner can use

- `setPositionFeeBasisPoints` used to adjust the position fee between 1 and 200 basis points

## Oracle System

Prices are provided by an off-chain oracle system:

Whenever a function is executed where the user sends a transaction, the asset prices are updated to have the current price, ensuring the correct token price.

The protocol obtains the updated prices instantly thanks to a library we have added with the name PRICECONVERTER, which utilizes the AggregatorV3Interface interface from Chainlink.

## Fees and Pricing

We support:

- liquidation fees -> 10% of the remaining collateral after fees and PnL is accounted for
- position fees -> changeable percentage of the amount of position increased. Starts with 1%
- borrowing fees -> 10% yearly rate

## Structure

There is one contract (`PerpetualGuardian`) and one library(`PriceConverter`) for receiving oracle prices.

The PerpetualGuardian contract inherits ERC4626, where we use it to create a vault for deposits and withdrawals by Liquidity Providers.

In it, we can also find functions to open positions for traders and close options.

One function created to maintain the protocol's security is called "liquidate," where any user other than the trader with a bad "position" can call it to liquidate the bad position.

We also maintain functions that calculate the positions to ensure they are safe for the protocol before opening and while they are open

The library used to receive oracle prices, "PriceConverter," uses the interface of the ChainLink library "AggregatorV3." We receive the price of the ETH/USD asset, allowing us to obtain the current price at any given moment.

## Implementation details

We keep all the positions we use the following struct

```
struct  Position {
uint256 collateral; //in DAI
uint256 avgEthPrice; // changes when the position is changed. We use it to account for PnL
uint256 ethAmount;
bool isLong; //indicates if the position is long or short
uint256 lastChangeTimestamp; // Used for borrowing fee
}
```

---

We use this struct to keep count of Open Interest. We have two instances of it - for short and long positions. Could be merged together in the future.

```
struct  PositionsSummary {
uint256 sizeInDai;
uint256 sizeInETH;
}
```

---

`totalAssets` is calculated by taking into consideration the DAI tokens in the vault and adding the PnL of traders as well as removing the collateral added from traders.

---

# Known risks and limitations

- We are aware of precision issues, due to the fact that in some places we keep `DAI` with precision of 1e18, but in others (Like totalAssets()) we keep it as is.
- One trader can only open one position at a time.
- We thought last moment that it might be useful to have a separate `closePosition` func, so the trader can close the position without much calculations.
- Vulnerable to Inflation Attack.

Apologies for the not amazing README.
