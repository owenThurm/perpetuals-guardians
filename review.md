# Mission 1 Review Notes


## Functionality Notes


### Liquidity Providers can deposit and withdraw liquidity

This functionality looks good! I like your decisions to simply create wrapper functions around the ERC4626 functions and implement the checkForAvailableLiquidity modifier for the removeLiquidity function.

And of course you have the TODO to override and "hide"/"deactivate" the redeem/withdraw/deposit/mint functions.

### A way to get the realtime price of the asset being traded.

This functionality is present! I like the addition of the getConversionRateinEth and getConversionRateinDai functions, these will prove useful!

One note about the PriceConverter contract is I see you use 1000000000000000000 to represent 1 with 18 decimals, Solidity offers ether as a unit to make this a bit more readable. So we can replace 1000000000000000000 with 1 ether.


### Traders can open a perpetual position for BTC, with a given size and collateral.

We have an openPosition function which correctly transfers the collateral from the user and opens a perpetual position while recording the trader's average price for the position.

One thing I noticed that may pose issues is that the currentETHPrice is based on a single wei of ether, rather than getDaiValue(1 ether). This pricing is consistent for all functions at the moment, so the only concern would potentially be rounding issues due to a lack of precision in the resulting daiValue.

Additionally, it looks like the size parameter is a raw dollar amount that doesn't allow for fractions of a dollar -- you might consider allowing this value to have a certain number of decimals to support opening positions with a size of $1,000.50 etc...

In fact you can engineer the decimals of your systems USD representation such that decimalsForUSD - decimalsFromPriceFeed = decimalsForActualToken.

For example:

If I want to get an amount of ETH as a result, using an input USD amount and the result from a price feed, I might do the following:


* I know the price feed has 8 decimals of precision, I want to represent ether amounts -- ETH traditionally has 18 decimals.
* So I might represent USD in my system with 18 + 8 decimals of precision. E.g. 1e26 = 1 USD
* This way when I divide the USD value by the result of the price feed we get 26 - 8 decimals = 18 decimals, which is the correct decimal number for my token!

You could also generalize this to work for any token with any amount of decimals by introducing an "adjustment factor" for the priceFeed of each token. This is similar to the 1e10 adjustment you already make in the getPrice function.

For example:

* I want to be able to represent Ether amounts as well as USDC amounts in my system. But Ether has 18 decimals and USDC has 6 decimals.
* So I will choose to represent USD values with 30 decimals, ether prices will be adjusted up to 12 decimals (adjustment factor of 1e4), usdc prices will be adjusted up to 24 decimals (adjustment factor of 16).
* This way for ether: A USD amount (1e30 decimals) / the adjusted ether price (1e12 decimals) = Ether decimals (1e18 decimals)
* And for usdc: A USD amount (1e30 decimals) / the adjusted usdc price (1e24 decimals) = USDC decimals (1e6 decimals)

Essentially this would introduce an assetAdjustmentFactor mapping to the PriceConverter, whereby instead of always returning `answer * 10000000000`, you might return `answer * assetAdjustmentFactor[asset]`.


I like the approach of updating the position summary at the end, this makes accounting for net open interest and pnl very easy!


### Traders can increase the size of a perpetual position.

I like the way you handled the computation of the avgPrice, this functionality looks good!


### Traders can increase the collateral of a perpetual position.

This logic looks great!


### Traders cannot utilize more than a configured percentage of the deposited liquidity.

The checkForAvailableLiquidity modifier will do a great job of this!


### Liquidity providers cannot withdraw liquidity that is reserved for positions.

The checkForAvailableLiquidity modifier will do a great job of this!




## Suggestions

- Use 1 ether instead of 1000000000000000000 in the PriceConverter contract for readability
- Consider modifying the representation for USD (or size/additionalDai amounts) such that fractions of a dollar can be represented and a wide range of token decimals can be supported (described above).
