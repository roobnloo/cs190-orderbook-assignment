// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {IOrderbook} from "../src/IOrderbook.sol";

/// @title OrderbookTestBasic
/// @notice Single sanity-check test that exercises a market order against
///         resting limit orders on both sides. This test **fails by default**
///         against the shipped stub — making it pass is part of the
///         assignment.
contract OrderbookTestBasic is Test {
    MockERC20 internal base;
    MockERC20 internal quote;
    Orderbook internal book;

    address internal maker = address(0xA11CE);
    address internal taker = address(0xB0B);

    uint256 internal constant ONE = 1e18;

    function setUp() public {
        base = new MockERC20("Mock1", "M1");
        quote = new MockERC20("Mock2", "M2");
        book = new Orderbook(address(base), address(quote));

        // Maker has both tokens so it can place limits on both sides.
        base.mint(maker, 1_000 * ONE);
        quote.mint(maker, 1_000_000 * ONE);

        // Taker has both tokens so it can take both sides via market orders.
        base.mint(taker, 1_000 * ONE);
        quote.mint(taker, 1_000_000 * ONE);

        vm.prank(maker);
        base.approve(address(book), type(uint256).max);
        vm.prank(maker);
        quote.approve(address(book), type(uint256).max);

        vm.prank(taker);
        base.approve(address(book), type(uint256).max);
        vm.prank(taker);
        quote.approve(address(book), type(uint256).max);
    }

    function test_ClearOrderbook() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 101, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 80, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 99, ONE);

        assertEq(book.getAsksCount(), 2, "ask should rest");
        assertEq(book.getBidsCount(), 2, "bid should rest");

        vm.prank(taker);
        book.clear();
        assertEq(book.getAsksCount(), 0, "asks should be cleared");
        assertEq(book.getBidsCount(), 0, "bids should be cleared");
    }

    function test_placeLimitOrderReturnsId() public {
        vm.prank(maker);
        assertEq(
            book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE),
            1,
            "id should be 1"
        );

        vm.prank(maker);
        assertEq(
            book.placeLimitOrder(IOrderbook.Side.SELL, 101, ONE),
            2,
            "id should be 2"
        );

        vm.prank(maker);
        assertEq(
            book.placeLimitOrder(IOrderbook.Side.BUY, 80, ONE),
            3,
            "id should be 3"
        );

        book.clear();

        vm.prank(maker);
        assertEq(
            book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE),
            1,
            "id should be 1"
        );
    }

    function test_midPrice() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 98, ONE);
        assertEq(book.getMidPrice(), 99);

        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 90, ONE);
        assertEq(book.getMidPrice(), 99);

        book.clear();
        vm.expectRevert();
        book.getMidPrice();
    }

    function test_marketOrderWithNoLimits() public {
        assertEq(book.getBidsCount(), 0);
        assertEq(book.getAsksCount(), 0);
        vm.prank(taker);
        vm.expectRevert();
        book.placeMarketOrder(IOrderbook.Side.BUY, ONE);

        vm.prank(taker);
        vm.expectRevert();
        book.placeMarketOrder(IOrderbook.Side.SELL, ONE);
    }

    function test_simpleMarketBuy() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        assertEq(book.getAsksCount(), 1);

        assertEq(base.balanceOf(address(book)), ONE);
        assertEq(base.balanceOf(maker), 999 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_000 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.BUY, ONE);

        assertEq(base.balanceOf(address(book)), 0);
        assertEq(base.balanceOf(maker), 999 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_100 * ONE);
        assertEq(base.balanceOf(taker), 1_001 * ONE);
        assertEq(quote.balanceOf(taker), 999_900 * ONE);
        assertEq(book.getAsksCount(), 0);
    }

    function test_simpleMarketSell() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 100, ONE);
        assertEq(book.getBidsCount(), 1);

        assertEq(quote.balanceOf(address(book)), 100 * ONE);
        assertEq(base.balanceOf(maker), 1_000 * ONE);
        assertEq(quote.balanceOf(maker), 999_900 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.SELL, ONE);

        assertEq(quote.balanceOf(address(book)), 0);
        assertEq(base.balanceOf(maker), 1_001 * ONE);
        assertEq(quote.balanceOf(maker), 999_900 * ONE);
        assertEq(base.balanceOf(taker), 999 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_100 * ONE);
        assertEq(book.getBidsCount(), 0);
    }

    function test_marketBuyWithWalking() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 200, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        assertEq(book.getAsksCount(), 3);

        assertEq(base.balanceOf(maker), 997 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_000 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.BUY, 3 * ONE);

        assertEq(base.balanceOf(maker), 997 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_400 * ONE);
        assertEq(base.balanceOf(taker), 1_003 * ONE);
        assertEq(quote.balanceOf(taker), 999_600 * ONE);
        assertEq(book.getAsksCount(), 0);
    }

    function test_marketBuyMatchAble() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 200, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        assertEq(book.getAsksCount(), 3);

        assertEq(base.balanceOf(maker), 997 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_000 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.BUY, 10 * ONE);

        assertEq(base.balanceOf(maker), 997 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_400 * ONE);
        assertEq(base.balanceOf(taker), 1_003 * ONE);
        assertEq(quote.balanceOf(taker), 999_600 * ONE);
        assertEq(book.getAsksCount(), 0);
    }

    function test_marketBuyWalkingPartialFill() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 200, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 300, 10 * ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 400, 10 * ONE);
        assertEq(book.getAsksCount(), 5);

        assertEq(base.balanceOf(maker), 977 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_000 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.BUY, 5 * ONE);

        assertEq(base.balanceOf(maker), 977 * ONE);
        assertEq(quote.balanceOf(maker), 1_001_000 * ONE);
        assertEq(base.balanceOf(taker), 1_005 * ONE);
        assertEq(quote.balanceOf(taker), 999_000 * ONE);
        assertEq(book.getAsksCount(), 2);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.BUY, 8 * ONE);

        assertEq(base.balanceOf(maker), 977 * ONE);
        assertEq(quote.balanceOf(maker), 1_003_400 * ONE);
        assertEq(base.balanceOf(taker), 1_013 * ONE);
        assertEq(quote.balanceOf(taker), 996_600 * ONE);
        assertEq(book.getAsksCount(), 1);
    }

    function test_marketSellWalkingMatchAble() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 200, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 100, ONE);
        assertEq(book.getBidsCount(), 3);

        assertEq(base.balanceOf(maker), 1_000 * ONE);
        assertEq(quote.balanceOf(maker), 999_600 * ONE);
        assertEq(base.balanceOf(taker), 1_000 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_000 * ONE);

        vm.prank(taker);
        book.placeMarketOrder(IOrderbook.Side.SELL, 10 * ONE);

        assertEq(base.balanceOf(maker), 1_003 * ONE);
        assertEq(quote.balanceOf(maker), 999_600 * ONE);
        assertEq(base.balanceOf(taker), 997 * ONE);
        assertEq(quote.balanceOf(taker), 1_000_400 * ONE);
        assertEq(book.getBidsCount(), 0);
    }

    function test_insuffMakerFund() public {
        assertEq(base.balanceOf(maker), 1_000 * ONE);
        assertEq(book.getAsksCount(), 0);

        vm.prank(maker);
        vm.expectRevert();
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, 1_001 * ONE);
        assertEq(base.balanceOf(maker), 1_000 * ONE);
        assertEq(book.getAsksCount(), 0);
    }

    function test_limitOrderTokenLock() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 400, 10 * ONE);

        assertEq(book.getAsksCount(), 2);
        assertEq(base.balanceOf(maker), 989 * ONE);
        assertEq(quote.balanceOf(maker), 1_000_000 * ONE);
        assertEq(base.balanceOf(address(book)), 11 * ONE);

        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 100, ONE);
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.BUY, 300, 10 * ONE);

        assertEq(book.getBidsCount(), 2);
        assertEq(base.balanceOf(maker), 989 * ONE);
        assertEq(quote.balanceOf(maker), (1_000_000 - 3_100) * ONE);
        assertEq(quote.balanceOf(address(book)), 3_100 * ONE);
    }
}
