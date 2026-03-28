const assert = require("assert");

const TilapiaSupplyChain = artifacts.require("TilapiaSupplyChain");

async function expectRevert(promise, expectedMessage) {
	try {
		await promise;
		assert.fail("Expected transaction to revert");
	} catch (error) {
		assert(
			error.message.includes(expectedMessage),
			`Expected revert message to include "${expectedMessage}", got "${error.message}"`
		);
	}
}

contract("TilapiaSupplyChain", function (accounts) {
	const admin = accounts[0];
	const farmer = accounts[1];
	const distributor = accounts[2];
	const outsider = accounts[3];

	let supplyChain;

	beforeEach(async function () {
		supplyChain = await TilapiaSupplyChain.new({ from: admin });
		await supplyChain.authorizeRole(farmer, "farmer", true, { from: admin });
		await supplyChain.authorizeRole(distributor, "distributor", true, { from: admin });
	});

	it("deploys with the admin set to the deployer", async function () {
		const currentAdmin = await supplyChain.admin();
		assert.equal(currentAdmin, admin, "admin should be the deployer");
	});

	it("authorizes roles and registers a product", async function () {
		const farmerAccess = await supplyChain.isAuthorized(farmer);
		const distributorAccess = await supplyChain.isAuthorized(distributor);
		assert.equal(farmerAccess[0], true, "farmer should be authorized");
		assert.equal(farmerAccess[1], false, "farmer should not be a distributor");
		assert.equal(distributorAccess[0], false, "distributor should not be a farmer");
		assert.equal(distributorAccess[1], true, "distributor should be authorized");

		await supplyChain.registerProduct("Tilapia Premium", "Lake Farm", 100, { from: farmer });

		const productCount = await supplyChain.productCount();
		assert.equal(productCount.toString(), "1", "product count should increment");

		const exists = await supplyChain.productExists(1);
		assert.equal(exists, true, "product should exist");

		const product = await supplyChain.getProduct(1);
		assert.equal(product[0].toString(), "1", "product id mismatch");
		assert.equal(product[1], "Tilapia Premium", "batch name mismatch");
		assert.equal(product[2], "Lake Farm", "origin mismatch");
		assert.equal(product[3].toString(), "100", "quantity mismatch");
		assert.equal(product[5], farmer, "current owner mismatch");
		assert.equal(product[6], "Created", "status mismatch");

		const ownerHistory = await supplyChain.getOwnerHistory(1);
		assert.equal(ownerHistory.length, 1, "owner history should contain one entry");
		assert.equal(ownerHistory[0], farmer, "owner history should begin with the farmer");
	});

	it("registerBatch creates multiple products", async function () {
		await supplyChain.registerBatch(["Batch A", "Batch B"], "Delta Farm", [25, 50], { from: farmer });

		const productCount = await supplyChain.productCount();
		assert.equal(productCount.toString(), "2", "batch registration should create two products");

		const firstProduct = await supplyChain.getProduct(1);
		const secondProduct = await supplyChain.getProduct(2);
		assert.equal(firstProduct[1], "Batch A", "first batch name mismatch");
		assert.equal(secondProduct[1], "Batch B", "second batch name mismatch");
		assert.equal(firstProduct[2], "Delta Farm", "batch origin mismatch");
		assert.equal(secondProduct[2], "Delta Farm", "batch origin mismatch");
	});

	it("transfers ownership, prices the product, and confirms delivery", async function () {
		await supplyChain.registerProduct("Export Tilapia", "Coastal Farm", 80, { from: farmer });
		await supplyChain.transferOwnership(1, distributor, { from: farmer });

		let product = await supplyChain.getProduct(1);
		assert.equal(product[5], distributor, "current owner should be the distributor");
		assert.equal(product[6], "InTransit", "status should be InTransit after transfer");

		const ownerHistory = await supplyChain.getOwnerHistory(1);
		assert.equal(ownerHistory.length, 2, "owner history should include farmer and distributor");
		assert.equal(ownerHistory[0], farmer, "first owner should be farmer");
		assert.equal(ownerHistory[1], distributor, "second owner should be distributor");

		await supplyChain.setPrice(1, 12, { from: farmer });
		const price = await supplyChain.getPrice(1);
		assert.equal(price[0].toString(), "12", "stored price mismatch");
		assert.equal(price[1].toString(), "960", "total value mismatch");

		await supplyChain.setMinimumTransit(0, { from: admin });
		await supplyChain.confirmDelivery(1, { from: distributor });

		product = await supplyChain.getProduct(1);
		assert.equal(product[6], "Delivered", "status should be Delivered after confirmation");
	});

	it("stores and verifies QR hashes", async function () {
		await supplyChain.registerProduct("QR Tilapia", "Inland Farm", 30, { from: farmer });
		await supplyChain.setQRHash(1, "QR:1:INLAND", { from: farmer });

		const matches = await supplyChain.verifyQRHash(1, "QR:1:INLAND");
		const doesNotMatch = await supplyChain.verifyQRHash(1, "QR:WRONG");

		assert.equal(matches, true, "QR hash should match the stored payload");
		assert.equal(doesNotMatch, false, "QR hash should reject the wrong payload");
	});

	it("reverts for invalid or unauthorized actions", async function () {
		await expectRevert(
			supplyChain.registerProduct("Bad Batch", "Farm", 0, { from: farmer }),
			"Quantity must be greater than zero"
		);

		await expectRevert(
			supplyChain.authorizeRole(outsider, "invalid", true, { from: admin }),
			"Invalid role"
		);

		await supplyChain.registerProduct("Tilapia Prime", "River Farm", 40, { from: farmer });

		await expectRevert(
			supplyChain.transferOwnership(1, outsider, { from: farmer }),
			"New owner must be an authorized distributor"
		);

		await expectRevert(
			supplyChain.confirmDelivery(1, { from: distributor }),
			"Product is not in transit"
		);
	});
});
