// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./proxy/ProxyRegistry.sol";
import "./GolfJunkiesMintPass1155.sol";
import "./GolfJunkiesFounderToken.sol";

contract GolfJunkies is  ERC721Enumerable, ReentrancyGuard, Ownable {

    uint8 public constant MINT_PHASE_OWNER = 0;
    uint8 public constant MINT_PHASE_MINT_PASS = 1;
    uint8 public constant MINT_PHASE_PUBLIC = 2;
    uint8 public _mintPhase = MINT_PHASE_OWNER;
    address payable public _mintPassAddress;
    address payable public _golfJunkiesFounderTokenAddress;
    address public _whitelistToken;
    uint256 public constant MAX_SUPPLY = 5000; // Maximum supply of 10K
    uint256 public price; // Price per token
    uint256 public _maxPerTx; // Maximum number of tokens that can be minted in one request
    mapping(uint256 => uint256) private _allocatedTokens; // Mapping to keep track of allocated tokens and help with the random allocation

    /**
     * @dev Constructor
     *
     * @param name_ name of the token
     * @param symbol_ symbol of the token
     * @param price_ price per token
     * @param maxPerTx_ maximum tokens to be minted in one transaction
     */
    constructor(
        string memory name_, 
        string memory symbol_,
        uint256 price_,
        uint256 maxPerTx_,
        address payable mintPassAddress_
    ) 
        ERC721(name_, symbol_)
    {
        price = price_;
        _maxPerTx = maxPerTx_;
        _mintPassAddress = mintPassAddress_;
    }

    /**
     * @dev Sets the golf junkies address founder token for the mint pass redeem
     *      we mint a golf junkies token for each mint pass redeemed
     *
     * @param newAddress_ new golf junkies contract address
     */
    function setGolfJunkiesFounderTokenAddress(address payable newAddress_) external onlyOwner {
        require(newAddress_ != address(0));
        _golfJunkiesFounderTokenAddress = newAddress_;
    }

    /**
     * @dev Sets the mint phase, see MINT_PHASE_* constants for options
     *
     * @param newMintPhase_ new mint phase for the GJ
     */
    function setMintPhase(uint8 newMintPhase_) external onlyOwner {
        require(newMintPhase_ <= MINT_PHASE_PUBLIC, "E10");
        _mintPhase = newMintPhase_;
    }

    /**
     * @dev withdraws the eth from the contract to the treasury
     *
     * @param treasury_ treasury address for the eth to be sent to
     */
    function withdraw(address treasury_) external onlyOwner nonReentrant {
		payable(treasury_).transfer(address(this).balance);
	}

    /**
     * @dev run some shared validation before minting
     *
     * @param quantity_ number of tokens to be minted
     * @param totalSupply_ current total supply
     * @param checkPrice_ flag to indicate if the price needs to be checked (mints that cost eth)
     */
    function checkBeforeMint(uint quantity_, uint totalSupply_, bool checkPrice_) internal view {
        require(quantity_ <= _maxPerTx, "E20");
        require(MAX_SUPPLY >= (totalSupply_ + quantity_), "E30");
        require(!checkPrice_ || msg.value >= (price * quantity_), "E40");
    }

    /**
     * @dev Allows the owner to mint a quantity of tokens, once the owner has 
     *      minted the required tokens then setMintPhase must be called to
     *      open the mint pass mint
     *
     * @param quantity_ number of tokens to be randomly minted to the owner
     */
    function ownerMint(uint quantity_) external nonReentrant onlyOwner {
        require(_mintPhase == MINT_PHASE_OWNER, "E50");
        checkBeforeMint(quantity_, totalSupply(), false);
        _randomMint(_random(), msg.sender, quantity_);
    }

    /**
     * @dev Allows the founder contract to mint Golf Junkies to a founder address
     * 
     * @param to_ address to mint the tokens to
     * @param quantity_ number of tokens to be randomly minted to the owner
     */
    function founderMint(address to_, uint quantity_) external nonReentrant {
        require(msg.sender == _golfJunkiesFounderTokenAddress, "E65");
        checkBeforeMint(quantity_, super.totalSupply(), false);
        _randomMint(_random(), to_, quantity_);
    }

    /**
     * @dev Mints a quantity of tokens to the sender address, this can only be 
     *      called once the other phases have successfully run. Along with
     *      the tokens the correct ammount of eth will need to be sent with the
     *      request
     *
     * @param quantity_ number of tokens to be minted
     */
    function mint(uint quantity_) external payable nonReentrant {
        require(_mintPhase == MINT_PHASE_PUBLIC, "E110");
        checkBeforeMint(quantity_, totalSupply(), true);
        _randomMint(_random(), msg.sender, quantity_);
    }

    /**
     * @dev Override the base _baseURI() to set the IPFS location.
     *
     * @return string IPFS uri
     */
    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://QmYqB5aufQbfySt42L17h5nvKzAVUL25SWBSiJkY6pxkrd/";
    }

    /**
     * @dev Creates a random string to seed the mint tokens
     */
    function _random() internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(
                    msg.sender,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    blockhash(block.number - 1),
                    block.difficulty
                )
            )
        );
    }

    /**
     * @dev Callback function used by VRF Coordinator, this is where the tokens are minted
     *      based on the details stored
     *
     * @param randomness_ the random result
     */
    function _randomMint(uint256 randomness_, address to, uint256 amount) internal {

        // Calculate the remaining tokens and calculate an available index
        uint256 remaining =  MAX_SUPPLY - super.totalSupply();

        // loop through each token requested
        for(uint x = 0; x < amount; x++){
            require(remaining > 0);
            uint256 i = uint256(keccak256(abi.encode(randomness_, x))) % remaining;
            uint256 index = _allocatedTokens[i] == 0 ? i : _allocatedTokens[i];
            _allocatedTokens[i] = _allocatedTokens[remaining - 1] == 0 ? remaining - 1 : _allocatedTokens[remaining - 1];
            
            _safeMint(to, index + 1); // no zero token id

            remaining--; // OK as check is at start of loop
            
            
        }

    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        GolfJunkiesFounderToken golfJunkiesFounderToken = GolfJunkiesFounderToken(_golfJunkiesFounderTokenAddress);
        uint256 mintPassTotalSupply = GolfJunkiesMintPass1155(_mintPassAddress).totalSupply(1);
        
        uint256 reservedForFounderToken = ((golfJunkiesFounderToken.MAX_SUPPLY() - mintPassTotalSupply) * golfJunkiesFounderToken._golfJunkiesQuantity()) // Founder tokens - the amount to be minted by mint pass * by the golf junkies per founder token
                            + 
                            (mintPassTotalSupply * golfJunkiesFounderToken._golfJunkiesMintPassQuantity()); // mint pass * by the golf junkies per mint pass token

        return super.totalSupply() + reservedForFounderToken;
    }

    /**
     * @dev to receive remaining eth from the link exchange
     */
    receive() external payable {}

    /**
     * PAPER FUNCTIONS    
     */

     function getClaimIneligibilityReason(address userWallet, uint256 quantity) public view returns (string memory) {

         if(_mintPhase != MINT_PHASE_PUBLIC){
             return "NOT_LIVE";
         } 

         return "";
     }

     function unclaimedSupply() public view returns (uint256) {
         return MAX_SUPPLY - totalSupply();
     }

     function claimTo(address userWallet, uint256 quantity) public payable {
        require(_mintPhase == MINT_PHASE_PUBLIC, "E110");
        checkBeforeMint(quantity, totalSupply(), true);
        _randomMint(_random(), userWallet, quantity);
     }
}
