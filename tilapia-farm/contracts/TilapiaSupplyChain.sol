// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title TilapiaSupplyChain
/// @author Tilapia Farm Exam — GitHub Copilot
/// @notice Tracks tilapia product lifecycle data from registration to delivery.
/// @dev Uses Solidity ^0.8.0 checked arithmetic, so integer overflows and underflows revert by default.
contract TilapiaSupplyChain {
	/// @notice Defines the lifecycle stages of a product.
	enum Status {
		/// @notice Product record is created and registered.
		Created,
		/// @notice Product is currently being transported.
		InTransit,
		/// @notice Product has been delivered to destination.
		Delivered
	}

	/// @notice Represents a tracked tilapia product batch.
	struct Product {
		/// @notice Unique identifier of the product record.
		uint productId;
		/// @notice Batch name or product type.
		string batchName;
		/// @notice Farm location where the product originated.
		string origin;
		/// @notice Quantity of product in kilograms.
		uint quantity;
		/// @notice Unix timestamp when the product was created.
		uint timestamp;
		/// @notice Wallet address of the current owner.
		address currentOwner;
		/// @notice Current lifecycle status of the product.
		Status status;
	}

	/// @notice Address of the contract deployer and system administrator.
	address public admin;

	/// @notice Stores all registered products by product ID.
	mapping(uint => Product) public products;

	/// @notice Stores full ownership transfer history per product ID.
	mapping(uint => address[]) public ownerHistory;

	/// @notice Whitelist of addresses authorized to register farm products.
	mapping(address => bool) public authorizedFarmers;

	/// @notice Whitelist of addresses authorized to handle distribution.
	mapping(address => bool) public authorizedDistributors;

	/// @notice Auto-incrementing counter used to assign product IDs.
	uint public productCount;

	/// @notice Stores product price per kilogram by product ID.
	mapping(uint => uint) public productPrice;

	/// @notice Stores minimum required in-transit time before delivery confirmation.
	uint public minimumTransitSeconds = 3600;

	/// @notice Stores hashed QR payload references by product ID.
	mapping(uint => bytes32) public productQRHash;

	/// @notice Emitted when a new product is registered by a farmer.
	event ProductRegistered(uint productId, address farmer, uint timestamp);

	/// @notice Emitted when ownership of a product changes.
	event OwnershipTransferred(uint productId, address from, address to);

	/// @notice Emitted when a product status is updated.
	event StatusUpdated(uint productId, Status newStatus);

	/// @notice Emitted when a product price per kilogram is set.
	event PriceSet(uint productId, uint pricePerKg, address setBy);

	/// @notice Initializes the contract and sets the deployer as admin.
	constructor() {
		admin = msg.sender;
	}

	/// @notice Restricts execution to the contract administrator.
	modifier onlyAdmin() {
		require(msg.sender == admin, "Caller is not the admin");
		_;
	}

	/// @notice Restricts execution to authorized farmer addresses.
	modifier onlyFarmer() {
		require(authorizedFarmers[msg.sender], "Caller is not an authorized farmer");
		_;
	}

	/// @notice Restricts execution to authorized distributor addresses.
	modifier onlyDistributor() {
		require(authorizedDistributors[msg.sender], "Caller is not an authorized distributor");
		_;
	}

	/// @notice Grants or removes role authorization for an account.
	/// @param account The wallet address to update.
	/// @param role The target role name: farmer or distributor.
	/// @param status True to authorize, false to deauthorize.
	function authorizeRole(address account, string memory role, bool status) public onlyAdmin {
		bytes32 roleHash = keccak256(bytes(role));

		if (roleHash == keccak256(bytes("farmer"))) {
			authorizedFarmers[account] = status;
		} else if (roleHash == keccak256(bytes("distributor"))) {
			authorizedDistributors[account] = status;
		} else {
			revert("Invalid role");
		}
	}

	/// @notice Revokes a role from an account by setting authorization to false.
	/// @param account The wallet address to update.
	/// @param role The target role name: farmer or distributor.
	function revokeRole(address account, string memory role) public onlyAdmin {
		authorizeRole(account, role, false);
	}

	/// @notice Registers a new tilapia product batch on-chain.
	/// @param _batchName The product batch name or type identifier.
	/// @param _origin The farm location where the batch originated.
	/// @param _quantity The quantity of the batch in kilograms.
	/// @return The newly assigned product ID.
	function registerProduct(string memory _batchName, string memory _origin, uint _quantity)
		public
		onlyFarmer
		returns (uint)
	{
		require(_quantity > 0, "Quantity must be greater than zero");
		require(bytes(_batchName).length > 0, "Batch name cannot be empty");
		require(bytes(_origin).length > 0, "Origin cannot be empty");

		productCount++;

		products[productCount] = Product({
			productId: productCount,
			batchName: _batchName,
			origin: _origin,
			quantity: _quantity,
			timestamp: block.timestamp,
			currentOwner: msg.sender,
			status: Status.Created
		});

		ownerHistory[productCount].push(msg.sender);

		emit ProductRegistered(productCount, msg.sender, block.timestamp);

		return productCount;
	}

	/// @notice Transfers product ownership from a farmer to an authorized distributor.
	/// @param _productId The ID of the product to transfer.
	/// @param _newOwner The distributor address that will receive ownership.
	function transferOwnership(uint _productId, address _newOwner) public onlyFarmer {
		require(products[_productId].productId != 0, "Product does not exist");
		require(_newOwner != address(0), "Invalid new owner address");
		require(
			products[_productId].currentOwner == msg.sender,
			"Caller is not the current product owner"
		);
		require(
			authorizedDistributors[_newOwner],
			"New owner must be an authorized distributor"
		);
		require(
			products[_productId].status == Status.Created,
			"Product has already been transferred"
		);

		products[_productId].currentOwner = _newOwner;
		products[_productId].status = Status.InTransit;

		ownerHistory[_productId].push(_newOwner);

		emit OwnershipTransferred(_productId, msg.sender, _newOwner);
		emit StatusUpdated(_productId, Status.InTransit);
	}

	/// @notice Confirms product delivery by the current distributor owner.
	/// @param _productId The ID of the product being delivered.
	function confirmDelivery(uint _productId) public onlyDistributor {
		require(products[_productId].productId != 0, "Product does not exist");
		require(
			products[_productId].currentOwner == msg.sender,
			"Only the current owner can confirm delivery"
		);
		require(
			products[_productId].status == Status.InTransit,
			"Product is not in transit"
		);
		require(
			block.timestamp >= products[_productId].timestamp + minimumTransitSeconds,
			"Minimum transit time not elapsed"
		);

		products[_productId].status = Status.Delivered;

		emit StatusUpdated(_productId, Status.Delivered);
	}

	/// @notice Returns the full ownership history for a product.
	/// @param _productId The ID of the product to query.
	/// @return The ordered list of owner addresses for the product.
	function getOwnerHistory(uint _productId) public view returns (address[] memory) {
		return ownerHistory[_productId];
	}

	/// @notice Returns full product details with a human-readable status label.
	/// @param _productId The ID of the product to query.
	/// @return id The product ID.
	/// @return batchName The product batch name.
	/// @return origin The product origin location.
	/// @return quantity The product quantity in kilograms.
	/// @return timestamp The Unix timestamp when the product was registered.
	/// @return currentOwner The current owner address of the product.
	/// @return status The human-readable lifecycle status.
	function getProduct(uint _productId)
		public
		view
		returns (
			uint id,
			string memory batchName,
			string memory origin,
			uint quantity,
			uint timestamp,
			address currentOwner,
			string memory status
		)
	{
		require(products[_productId].productId != 0, "Product does not exist");

		Product memory p = products[_productId];
		string memory statusLabel = statusToString(p.status);

		return (
			p.productId,
			p.batchName,
			p.origin,
			p.quantity,
			p.timestamp,
			p.currentOwner,
			statusLabel
		);
	}

	/// @notice Returns a product status as a human-readable string.
	/// @param _productId The ID of the product to query.
	/// @return The product status label.
	function getStatus(uint _productId) public view returns (string memory) {
		require(products[_productId].productId != 0, "Product does not exist");
		return statusToString(products[_productId].status);
	}

	/// @notice Converts a status enum value into its corresponding string label.
	/// @param s The status enum value to convert.
	/// @return The human-readable status label.
	function statusToString(Status s) internal pure returns (string memory) {
		if (s == Status.Created) return "Created";
		if (s == Status.InTransit) return "InTransit";
		return "Delivered";
	}

	/// @notice Checks whether a product ID exists in storage.
	/// @param _productId The ID of the product to check.
	/// @return True if the product exists, otherwise false.
	function productExists(uint _productId) public view returns (bool) {
		return products[_productId].productId != 0;
	}

	/// @notice Returns whether an account is authorized as farmer and distributor.
	/// @param account The address to check.
	/// @return isFarmer True if the address is an authorized farmer.
	/// @return isDistributor True if the address is an authorized distributor.
	function isAuthorized(address account) public view returns (bool isFarmer, bool isDistributor) {
		return (authorizedFarmers[account], authorizedDistributors[account]);
	}

	/// @notice Sets the price per kilogram for a product owned by the caller.
	/// @param _productId The ID of the product to price.
	/// @param _pricePerKg The price per kilogram to store.
	function setPrice(uint _productId, uint _pricePerKg) public onlyFarmer {
		require(products[_productId].productId != 0, "Product does not exist");
		require(
			products[_productId].currentOwner == msg.sender,
			"Caller is not the current product owner"
		);

		productPrice[_productId] = _pricePerKg;

		emit PriceSet(_productId, _pricePerKg, msg.sender);
	}

	/// @notice Returns unit price and computed total product value.
	/// @param _productId The ID of the product to evaluate.
	/// @return pricePerKg The stored price per kilogram.
	/// @return totalValue The computed value as pricePerKg multiplied by quantity.
	function getPrice(uint _productId) public view returns (uint pricePerKg, uint totalValue) {
		require(products[_productId].productId != 0, "Product does not exist");

		uint price = productPrice[_productId];
		uint value = price * products[_productId].quantity;

		return (price, value);
	}

	/// @notice Registers multiple products in a single transaction.
	/// @param _batchNames The list of batch names to register.
	/// @param _origin The common origin location for all batches.
	/// @param _quantities The list of quantities matching each batch name.
	/// @return productIds The list of newly created product IDs.
	function registerBatch(
		string[] memory _batchNames,
		string memory _origin,
		uint[] memory _quantities
	) public onlyFarmer returns (uint[] memory productIds) {
		require(_batchNames.length == _quantities.length, "Input array lengths must match");

		productIds = new uint[](_batchNames.length);

		for (uint i = 0; i < _batchNames.length; i++) {
			productIds[i] = registerProduct(_batchNames[i], _origin, _quantities[i]);
		}

		return productIds;
	}

	/// @notice Updates the minimum transit duration required before delivery confirmation.
	/// @param seconds_ The new minimum transit duration in seconds.
	function setMinimumTransit(uint seconds_) public onlyAdmin {
		minimumTransitSeconds = seconds_;
	}

	/// @notice Stores a hashed QR payload reference for a product.
	/// @param _productId The ID of the product.
	/// @param _qrPayload The QR payload string to hash and store.
	function setQRHash(uint _productId, string memory _qrPayload) public onlyFarmer {
		productQRHash[_productId] = keccak256(abi.encodePacked(_qrPayload));
	}

	/// @notice Verifies whether a QR payload matches the stored hash for a product.
	/// @param _productId The ID of the product.
	/// @param _qrPayload The QR payload string to validate.
	/// @return True if the payload hash matches the stored hash, otherwise false.
	function verifyQRHash(uint _productId, string memory _qrPayload) public view returns (bool) {
		return productQRHash[_productId] == keccak256(abi.encodePacked(_qrPayload));
	}
}
