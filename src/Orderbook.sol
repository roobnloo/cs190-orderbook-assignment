// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOrderbook} from "./IOrderbook.sol";

/// @dev Minimal ERC20 surface the orderbook needs. The provided `MockERC20`
///      implements all of these methods (plus `mint`).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

/// @title Orderbook (template)
/// @notice Skeleton to complete. The constructor, immutable
///         token wiring, and the two trivial getters are already done —
///         everything else reverts with `"NotImplemented"`.
///
///         You are free to add additional state, structs, errors, and
///         helper functions. The only hard constraints are:
///         (1) keep the `IOrderbook` ABI exactly as declared in the
///             interface (the grading harness depends on it), and
///         (2) keep `baseToken`/`quoteToken` as immutables set in the
///             constructor.
contract Orderbook is IOrderbook {
    IERC20 public immutable baseToken;
    IERC20 public immutable quoteToken;

    /// @dev Suggested events. These are a starting point — your
    ///      implementation may emit a different set, rename them, or omit
    ///      events entirely. Nothing in the grading harness depends on
    ///      these signatures.
    event OrderPlaced(
        uint256 indexed orderId,
        address indexed maker,
        Side side,
        uint256 price,
        uint256 amount
    );
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        uint256 fillAmount,
        uint256 fillPrice
    );
    event OrderCleared();

    struct LimitOrder {
        address maker;
        Side side;
        uint256 price;
        uint256 amount;
    }

    LimitOrder[] bidLimits; // increasing order by price
    LimitOrder[] askLimits; // decreasing order by price
    uint256 nextLimitOrderId = 1;

    constructor(address _baseToken, address _quoteToken) {
        require(_baseToken != address(0), "baseToken=0");
        require(_quoteToken != address(0), "quoteToken=0");
        require(_baseToken != _quoteToken, "base==quote");
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function getBaseToken() external view returns (address) {
        return address(baseToken);
    }

    function getQuoteToken() external view returns (address) {
        return address(quoteToken);
    }

    function placeLimitOrder(
        Side side,
        uint256 price,
        uint256 amount
    ) external returns (uint256) {
        if (amount == 0) {
            revert("Cannot place limit order with zero amount.");
        }
        if (side == Side.BUY) {
            // Lock amount quote from maker
            quoteToken.transferFrom(msg.sender, address(this), (amount * price) / 1e18);
            bidLimits.push(
                LimitOrder({
                    maker: msg.sender,
                    side: side,
                    price: price,
                    amount: amount
                })
            );
            uint256 curIdx = bidLimits.length - 1;
            uint256 nextIdx;
            LimitOrder memory temp;
            while (curIdx > 0) {
                // Keep bubbling the new order down until the sorted invariant is met
                // Last element is highest bid
                nextIdx = curIdx - 1;
                if (bidLimits[nextIdx].price >= price) {
                    temp = bidLimits[nextIdx];
                    bidLimits[nextIdx] = bidLimits[curIdx];
                    bidLimits[curIdx] = temp;
                    curIdx--;
                } else {
                    break;
                }
            }
        } else {
            // Lock amount base from maker
            baseToken.transferFrom(msg.sender, address(this), amount);
            askLimits.push(
                LimitOrder({
                    maker: msg.sender,
                    side: side,
                    price: price,
                    amount: amount
                })
            );
            uint256 curIdx = askLimits.length - 1;
            uint256 nextIdx;
            LimitOrder memory temp;
            while (curIdx > 0) {
                // Keep bubbling the new order down until the sorted invariant is met
                // Last element is lowest ask
                nextIdx = curIdx - 1;
                if (askLimits[nextIdx].price <= price) {
                    temp = askLimits[nextIdx];
                    askLimits[nextIdx] = askLimits[curIdx];
                    askLimits[curIdx] = temp;
                    curIdx--;
                } else {
                    break;
                }
            }
        }
        return nextLimitOrderId++;
    }

    function placeMarketOrder(Side side, uint256 amount) external {
        uint256 curId;
        uint256 remaining = amount;
        if (side == IOrderbook.Side.BUY) {
            if (askLimits.length == 0) {
                revert("No limit ask orders to trade against.");
            }
            while (remaining > 0 && askLimits.length > 0) {
                curId = askLimits.length - 1;
                if (askLimits[curId].amount >= remaining) {
                    askLimits[curId].amount -= remaining;
                    baseToken.transfer(msg.sender, remaining);
                    quoteToken.transferFrom(
                        msg.sender,
                        askLimits[curId].maker,
                        (remaining * askLimits[curId].price) / 1e18
                    );
                    remaining = 0;
                    if (askLimits[curId].amount == 0) {
                        askLimits.pop();
                    }
                } else {
                    baseToken.transfer(msg.sender, askLimits[curId].amount);
                    quoteToken.transferFrom(
                        msg.sender,
                        askLimits[curId].maker,
                        (askLimits[curId].amount * askLimits[curId].price) / 1e18
                    );
                    remaining -= askLimits[curId].amount;
                    askLimits.pop();
                }
            }
        } else {
            if (bidLimits.length == 0) {
                revert("No limit bid orders to trade against.");
            }
            while (remaining > 0 && bidLimits.length > 0) {
                curId = bidLimits.length - 1;
                if (bidLimits[curId].amount >= remaining) {
                    bidLimits[curId].amount -= remaining;
                    baseToken.transferFrom(
                        msg.sender,
                        bidLimits[curId].maker,
                        remaining
                    );
                    quoteToken.transfer(
                        msg.sender,
                        (remaining * bidLimits[curId].price) / 1e18
                    );
                    remaining = 0;
                    if (bidLimits[curId].amount == 0) {
                        bidLimits.pop();
                    }
                } else {
                    baseToken.transferFrom(
                        msg.sender,
                        bidLimits[curId].maker,
                        bidLimits[curId].amount
                    );
                    quoteToken.transfer(
                        msg.sender,
                        (bidLimits[curId].amount * bidLimits[curId].price) / 1e18
                    );
                    remaining -= bidLimits[curId].amount;
                    bidLimits.pop();
                }
            }
        }
    }

    function clear() external {
        // Transfer all the book tokens to original makers and delete the orders
        for (uint256 i = 0; i < bidLimits.length; i++) {
            quoteToken.transfer(
                bidLimits[i].maker,
                (bidLimits[i].amount * bidLimits[i].price) / 1e18
            );
        }
        for (uint256 i = 0; i < askLimits.length; i++) {
            baseToken.transfer(askLimits[i].maker, askLimits[i].amount);
        }
        delete bidLimits;
        delete askLimits;
        nextLimitOrderId = 1;
    }

    function getBidsCount() external view returns (uint256) {
        return bidLimits.length;
    }

    function getAsksCount() external view returns (uint256) {
        return askLimits.length;
    }

    function getMidPrice() external view returns (uint256) {
        uint256 numBids = bidLimits.length;
        uint256 numAsks = askLimits.length;
        if (numBids == 0 || numAsks == 0) {
            revert("Not enough bids or asks.");
        }
        return
            (bidLimits[numBids - 1].price + askLimits[numAsks - 1].price) / 2;
    }
}
