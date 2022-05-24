// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./proxy/ProxyRegistry.sol";
import "./GolfJunkiesMintPass1155.sol";
import "./GolfJunkies.sol";

contract GolfJunkiesFounderToken is  ERC721Enumerable, ReentrancyGuard, Ownable {

    uint8 public constant MINT_PHASE_OWNER = 0;
    uint8 public constant MINT_PHASE_MINT_PASS = 1;
    uint8 public constant MINT_PHASE_PUBLIC = 2;
    uint8 public _mintPhase = MINT_PHASE_OWNER;
    uint8 public _golfJunkiesQuantity;
    uint8 public _golfJunkiesMintPassQuantity;
    address payable public _mintPassAddress;
    address payable public _golfJunkiesAddress;
    uint256 public constant MAX_SUPPLY = 1000; // Maximum supply of 1K
    uint256 public price; // Price per token
    uint256 public _maxPerTx; // Maximum number of tokens that can be minted in one request

    /**
     * @dev Constructor
     *
     * @param name_ name of the token
     * @param symbol_ symbol of the token
     * @param price_ price per token
     * @param maxPerTx_ maximum tokens to be minted in one transaction
     * @param mintPassAddress_ mint pass contract address
     */
    constructor(
        string memory name_, 
        string memory symbol_,
        uint256 price_,
        uint256 maxPerTx_,
        address payable mintPassAddress_,
        uint8 golfJunkiesQuantity_,
        uint8 golfJunkiesMintPassQuantity_
    ) 
        ERC721(name_, symbol_)
    {
        price = price_;
        _maxPerTx = maxPerTx_;
        _mintPassAddress = mintPassAddress_;
        _golfJunkiesQuantity = golfJunkiesQuantity_;
        _golfJunkiesMintPassQuantity = golfJunkiesMintPassQuantity_;
    }

    /**
     * @dev Sets the golf junkies address for the mint pass redeem
     *      we mint a golf junkies token for each mint pass redeemed
     *
     * @param newAddress_ new golf junkies contract address
     */
    function setGolfJunkiesAddress(address payable newAddress_) external onlyOwner {
        require(newAddress_ != address(0));
        _golfJunkiesAddress = newAddress_;
    }

    /**
     * @dev Sets the golf junkies quantity, this is the number of tokens to mint per founder token
     *
     * @param quantity_ new golf junkies quantity
     */
    function setGolfJunkiesQuantity(uint8 quantity_) external onlyOwner {
        _golfJunkiesQuantity = quantity_;
    }

    /**
     * @dev Sets the golf junkies mint pass quantity, this is the number of tokens to mint per mint pass
     *
     * @param quantity_ new golf junkies quantity
     */
    function setGolfJunkiesMintPassQuantity(uint8 quantity_) external onlyOwner {
        _golfJunkiesMintPassQuantity = quantity_;
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
        _mintTokens(msg.sender, quantity_, quantity_ * _golfJunkiesQuantity);
    }

    /**
     * @dev Allows the mint pass owners to redeem the tokens for a GJ NFT. This
     *      is allowed any phase after owner mint
     *
     * @param quantity_ number of tokens to be randomly minted to the owner
     */
    function mintPassRedeem(uint quantity_) external nonReentrant {
        require(_mintPhase >= MINT_PHASE_MINT_PASS, "E60");
        checkBeforeMint(quantity_, super.totalSupply(), false);
        GolfJunkiesMintPass1155 mintPassContract = GolfJunkiesMintPass1155(_mintPassAddress);
        require(mintPassContract.balanceOf(msg.sender, 1) >= quantity_, "E70");
        mintPassContract.burnFrom(msg.sender, quantity_);
        _mintTokens(msg.sender, quantity_, quantity_ * _golfJunkiesMintPassQuantity);
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
        _mintTokens(msg.sender, quantity_, quantity_ * _golfJunkiesQuantity);
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
     * @dev Mints the tokens to the account
     *
     */
    function _mintTokens(address to, uint256 amount, uint256 golfJunkiesQuantity) internal {

        // Calculate the remaining tokens and calculate an available index
        uint256 currentTotalSupply = super.totalSupply();
        uint256 remaining =  MAX_SUPPLY - currentTotalSupply;

        // loop through each token requested
        for(uint x = 0; x < amount; x++){
            require(remaining > 0);

            _safeMint(to, currentTotalSupply + 1); // no zero token id

            remaining--; // OK as check is at start of loop
            currentTotalSupply++; // increase as we have minted one
        }

        if(golfJunkiesQuantity > 0) {
            GolfJunkies(_golfJunkiesAddress).founderMint(to, golfJunkiesQuantity);
        }
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply() + GolfJunkiesMintPass1155(_mintPassAddress).totalSupply(1);
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
        _mintTokens(userWallet, quantity, quantity * _golfJunkiesQuantity);
     }
}
