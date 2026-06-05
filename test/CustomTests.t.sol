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

    function test_marketBuy() public {
        vm.prank(maker);
        book.placeLimitOrder(IOrderbook.Side.SELL, 100, ONE);
        assertEq(book.getAsksCount(), 1);

        book.placeMarketOrder(IOrderbook.Side.SELL, ONE);
        assertEq(book.getAsksCount(), 0);
    }
}
