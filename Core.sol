// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Core is VRFConsumerBaseV2, ReentrancyGuard {

    /// @notice The name of this contract
    string public constant name = "Onifinance Project Core";

    //variables
    address public ofp;
    address public usdToken;

    VRFCoordinatorV2Interface VRF_COORDINATOR;
    uint64 public vrfSubscriptionId;
    address public vrfCoordinator = 0xAE975071Be8F8eE67addBC1A82488F1C24858067;
    bytes32 public vrfKeyHash = 0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd;
    uint32 public vrfCallbackGasLimit = 300000;
    uint16 public vrfRequestConfirmations = 3;
    uint32 public vrfNumWords =  7;
    uint256[] public vrfRandomWords;
    uint256 public vrfRequestId;
    
    uint public startMinting;
    
    uint public mintLimit = 20;
    uint public tokenPrice;

    uint public currentStep;
    uint public claimDate;

    address public governor;
    address public timelock;

    bool public tempLock;

    address public dev;
    uint public tokensDevRewarded;

    mapping (address => uint) public claimableBalance;
    mapping(uint => uint) public raffleAmounts;
    mapping(uint => uint) public raffleParticipantsNumber;
    mapping(uint => bool) public tokenIdRewarded;
    
    uint public totalProjectFunds;
    
    uint public ongoingRaffle;
    bool public selectedNextTokens;
    mapping(uint => uint[]) public selectedTokens;
    mapping(uint => mapping (uint => winnerInfo)) public raffleResult;
    address public utilityToken;//Onifinance DAO Utility Token.
    uint public utilityTokenAmount = 5_000e18;// 5 thousand utility Token per OFP
    bool public emergencyActive = false;
    uint public emergencyWithdrawalAmount;
    
    uint public totalSecondReward;
    uint public secondRewardDurationMinutes = (60*24*30*6);//6 months
    uint public secondRewardForEachMinute;
    uint public secondRewardStart;
    uint public secondRewardLastClaim;
    uint public secondRewardEnd;
    uint public secondMinutesRewarded = 0;

    uint public totalDevReward = 50_000_000e18; //50 million utility tokens
    uint public devRewardDurationMinutes = (5*365*24*60);//5 Years
    uint public devRewardStart;
    uint public devRewardEnd;
    uint public devRewardForEachMinute = totalDevReward / devRewardDurationMinutes;
    uint public minutesRewarded = 0;
    uint public lastDevRewardClaimDate;
    

    string Not_Time_Error = "it is not yet time";
    string Unautorized_Error = "unautorized";
    
    struct winnerInfo {
        uint IDToken;
        address owner;
        string name;
        string evidence;
    }
    
    //events
    
    event Step(uint currentStep);
    
    event AddClaimableBalance(address to, uint amount);
    
    event WithdrawClaimableBalance(address to, uint amount);
    
    event WithdrawUtilityToken(address to, uint amount);

    event EmergencyWithdrawal(address to, uint amount);
    
    //modifiers

    modifier gov() {
        require(msg.sender == timelock, Unautorized_Error);
        _;
    }

    modifier auth() {
        
        require(msg.sender == dev || msg.sender == timelock, Unautorized_Error);
        _;
        
    }

    modifier devShackles() {
        if(msg.sender == dev){
            (bool shackles, string memory message) = devShacklesData();
            require(!shackles, message);
        }
        
        _;
        
    }
    
    modifier emergency() {
        require(!emergencyActive, "The emergency has been activated");
        _;
    }

    /*
    currentStep == 0  1 USD Token x OFP for dev.
    currentStep == 1  request random words to chain link VRF.
    currentStep == 2  1 * 100.000 USD Token, 0 select token ids, 1 distribute.
    currentStep == 3  4 * 50.000 USD Token, 0 select token ids, 1 distribute.
    currentStep == 4  30 * 10.000 USD Token, 0 select token ids, 1 distribute.
    currentStep == 5  200 * 2.000 USD Token, 0 select token ids, 1 distribute.
    currentStep == 6  200 * 200 USD Token, 0 select token ids, 1 distribute.
    currentStep == 7  200 * 100 USD Token, 0 select token ids, 1 distribute.
    currentStep == 8  200 * 50 USD Token, 0 select token ids, 1 distribute.
    currentStep == 9  50 * 1.000 USD Token Twitter raffle.
    currentStep == 10 project funds, send project funds, 85% utility Tokens, set timelock minter, start second dev reward.
    currentStep == 11 40.000 USD Tokens for dev and start dev utility tokens reward.
    currentStep == 12  utility tokens for holders.
    */
    
    //constructor
    constructor(
        address dev_,
        address usdToken_,
        address ofp_,
        address utilityToken_,
        address governor_,
        address timelock_,
        uint startMinting_,
        uint64 subscriptionId
        
    ) 
    VRFConsumerBaseV2(vrfCoordinator)
    {   
        require(isContract(usdToken_), "usd token must be a contract.");
        require(isContract(ofp_), "ofp token must be a contract.");
        require(isContract(utilityToken_), "utility token must be a contract.");
        require(isContract(governor_), "governor must be a contract.");
        require(isContract(timelock_), "timelock must be a contract.");
        require(startMinting_ > block.timestamp, "the minting start date is incorrect.");
        
        VRF_COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        vrfSubscriptionId = subscriptionId;

        governor = governor_;
        timelock = timelock_;

        ofp = ofp_;
        usdToken = usdToken_;

        startMinting = startMinting_;
        
        dev = dev_;
        
        utilityToken = utilityToken_;

        tokenPrice = 100 * (10 ** Erc20(usdToken).decimals());//100 USD Token
        
        raffleAmounts[0] = tokenPrice * 1_000;// 100.000 USD Token
        raffleParticipantsNumber[0] = 1;

        raffleAmounts[1] = tokenPrice * 500;// 50.000 USD Token
        raffleParticipantsNumber[1] = 4;

        raffleAmounts[2] = tokenPrice * 100;// 10.000 USD Token
        raffleParticipantsNumber[2] = 30;

        raffleAmounts[3] = tokenPrice * 20;// 2.000 USD Token
        raffleParticipantsNumber[3] = 200;

        raffleAmounts[4] = tokenPrice * 2;// 200 USD Token
        raffleParticipantsNumber[4] = 200;

        raffleAmounts[5] = tokenPrice;//100 USD Token
        raffleParticipantsNumber[5] = 200;

        raffleAmounts[6] = tokenPrice / 2;//50 USD Token
        raffleParticipantsNumber[6] = 200;

        raffleAmounts[7] = tokenPrice * 10;// 1.000 USD Token
        raffleParticipantsNumber[7] = 50;

        totalProjectFunds = (tokenPrice * (OFP(ofp).maxTotalSupply() - 10)) - 
            (
                (raffleAmounts[0] * raffleParticipantsNumber[0]) + 
                (raffleAmounts[1] * raffleParticipantsNumber[1]) + 
                (raffleAmounts[2] * raffleParticipantsNumber[2]) + 
                (raffleAmounts[3] * raffleParticipantsNumber[3]) + 
                (raffleAmounts[4] * raffleParticipantsNumber[4]) + 
                (raffleAmounts[5] * raffleParticipantsNumber[5]) +
                (raffleAmounts[6] * raffleParticipantsNumber[6]) +
                (raffleAmounts[7] * raffleParticipantsNumber[7]) +
                ((tokenPrice / 100) * OFP(ofp).maxTotalSupply()) +
                (tokenPrice * 190)+
                (tokenPrice * 400)
            );

    }
    
    //internal functions

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }
    
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
       //Chainlink VRF
       //https://docs.chain.link/docs/chainlink-vrf/

        require(currentStep == 1 , Not_Time_Error);
        require(vrfRequestId == requestId, "bad request id");
        
        _setNextStep();

        vrfRandomWords = randomWords;
        
    }
    
    function _setNextStep() internal {
        
        currentStep++;
        emit Step(currentStep);
        
    }
    
    function _addClaimableBalance(address to, uint amount) internal {
        
        claimableBalance[to] += amount;
        emit AddClaimableBalance(to, amount);  
        
    }
    
    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'Transfer From failed'
        );
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'Transfer failed'
        );
    }
    
    //view functions
    
    function priceFor(uint amount) public view returns (uint price) {
        
        price = amount * tokenPrice;
        
    }

    function raffleResults(uint raffle) public view returns(winnerInfo[] memory){
        uint participantsNumber = raffleParticipantsNumber[raffle];
        if(participantsNumber == 0){
            return new winnerInfo[](0);
        }else{
            winnerInfo[] memory result = new winnerInfo[](participantsNumber);
            for (uint256 i = 0; i < participantsNumber; i++) {
                result[i] = raffleResult[raffle][i];
            }
            return result;
        }
        
    }

    function devShacklesData() public view returns(bool shackles, string memory message){
        if(block.timestamp < claimDate){
            shackles = true;
            message = Not_Time_Error;
        }else if(Governor(governor).hasActiveProposals()){
            shackles = true;
            message = "Found active proposals";
        }
    }
    
    function expand(uint randomValue, uint amount, uint max) public view returns (uint[] memory values) {
        
        require(amount <= max, "Invalid parameters");
        
        values = new uint[](amount);
        uint[] memory exist = new uint[](max + 1);
        uint i = 0;
        uint e = 0;

        while (e < amount){
            uint random = ( uint256(keccak256(abi.encode(randomValue, i))) % max) + 1;
            if(!tokenIdRewarded[random]){
                if(exist[random] == 0){
                    values[e] = random;
                    exist[random] = 1;
                    e++;
                }
            }
            i++;
        }
        return values;
        
    }
    
    //user functions

    function mint(address to, uint amount) external emergency nonReentrant {
        
        require(currentStep == 0, Not_Time_Error);
        require(block.timestamp >= startMinting, Not_Time_Error);
        require(amount <= mintLimit, "Execive Amount");
        require((OFP(ofp).totalSupply() + amount) <= OFP(ofp).maxTotalSupply(), "Not enough tokens");

        uint total = priceFor(amount);
        require(Erc20(usdToken).balanceOf(msg.sender) >= total, "Insufficient user balance");
        
        _safeTransferFrom(
        usdToken,
        msg.sender,
        address(this),
        total
        );
        
        OFP(ofp).mint(to, amount);
        
    }

    function withdrawClaimableBalance(address to, uint amount) external emergency nonReentrant {
        
        require(claimableBalance[msg.sender] >= amount, "Insufficient claimable balance");
        require(Erc20(usdToken).balanceOf(address(this)) >= amount, "Insufficient Contract balance");
        
        claimableBalance[msg.sender] -= amount;
        _safeTransfer(usdToken, to, amount);
        emit WithdrawClaimableBalance(to, amount);
        
    }

    function withdrawUtilityTokens(uint[] memory tokens) external emergency nonReentrant {
        require(currentStep == 12, Not_Time_Error);
        uint current = 0;
        uint amount = 0;
        while(current < tokens.length) {
            if(OFP(ofp).ownerOf(tokens[current]) == msg.sender){
                OFP(ofp).burn(tokens[current]);
                amount += utilityTokenAmount;
            }
            current++;
            
        }

        if(amount > 0){
            require(Erc20(utilityToken).balanceOf(address(this)) >= amount, "Insufficient Contract balance");
            _safeTransfer(utilityToken, msg.sender, amount);
            emit WithdrawUtilityToken(msg.sender, amount);
        }
    }
    
    function emergencyWithdraw(uint[] memory tokens) external nonReentrant {
        
        require(emergencyActive, Unautorized_Error);
        require(tokens.length > 0, "invalid token amount");
        
        uint current = 0;
        uint amount = 0;
        while(current < tokens.length) {
            if(OFP(ofp).ownerOf(tokens[current]) == msg.sender){
                OFP(ofp).burn(tokens[current]);
                amount += emergencyWithdrawalAmount;
            }
            current++;
            
        }
        
        if(amount > 0){
            _safeTransfer(usdToken, msg.sender, amount);
            emit EmergencyWithdrawal(msg.sender, amount);
        }
        
    }
    
    function sendProjectFunds() external emergency {
        
        require(currentStep == 10 , Not_Time_Error);
        
        _setNextStep(); 

        _safeTransfer(usdToken, timelock, totalProjectFunds);
        _safeTransfer(utilityToken, timelock, 850_000_000e18);
        UtilityToken(utilityToken).setMinter(timelock);

        secondRewardStart = block.timestamp;
        secondRewardLastClaim = block.timestamp;
        secondRewardEnd = (block.timestamp + (secondRewardDurationMinutes * 1 minutes));
        totalSecondReward = tokenPrice * 190;
        secondRewardForEachMinute = totalSecondReward / secondRewardDurationMinutes;
        
    }

    //restricted functions
    
    function setTempLock(bool temp) external gov {
        tempLock = temp;
    }
    
    function activateEmergency() external emergency {
        require(currentStep <= 10, Not_Time_Error);
        if(msg.sender == dev){
            require(block.timestamp > (startMinting + 30 days), Not_Time_Error);
            require(OFP(ofp).totalSupply() < 1000, "There are enough votes");
        }else if(msg.sender != timelock){
            require(block.timestamp > (startMinting + 60 days), Not_Time_Error);
            require(OFP(ofp).totalSupply() < 1000, "There are enough votes");
        }
        emergencyActive = true;
        emergencyWithdrawalAmount = Erc20(usdToken).balanceOf(address(this)) / OFP(ofp).totalSupply();
        OFP(ofp).update();
    }

    //Dev rewards
   
    function secondRewardMinutesPendingToClaim() public view returns(uint pendingMinutes){
        if(currentStep > 10){
            if(block.timestamp >= secondRewardEnd){
                pendingMinutes = secondRewardDurationMinutes - secondMinutesRewarded;
            }else{
                pendingMinutes = (block.timestamp - secondRewardLastClaim) / 60;
            }
        }
    }

    function pendingSecondReward() public view returns(uint amount, uint pendingMinutes){
        pendingMinutes = secondRewardMinutesPendingToClaim();
        amount = pendingMinutes * secondRewardForEachMinute;
    }
    
    function devRewardMinutesPendingToClaim() public view returns(uint pendingMinutes){
        if(currentStep > 11){
            if(block.timestamp >= devRewardEnd){
                pendingMinutes = devRewardDurationMinutes - minutesRewarded;
            }else{
                pendingMinutes = (block.timestamp - lastDevRewardClaimDate) / 60;
            }
        }
    }

    function pendingDevReward() public view returns(uint amount, uint pendingMinutes){
        pendingMinutes = devRewardMinutesPendingToClaim();
        amount = pendingMinutes * devRewardForEachMinute;
    }

    function requestDevFinalReward() external auth devShackles {
        
        require(currentStep == 11, "Not step yet.");
        require(!tempLock, "Pending found");
        
        claimDate = block.timestamp + 60 days;
        tempLock = true;
        
    }

    function claimDevReward() external auth devShackles emergency {
        
        if(currentStep == 0){

            if(tokensDevRewarded < OFP(ofp).totalSupply()){

                uint tokens = OFP(ofp).totalSupply() - tokensDevRewarded;
                uint amount = (tokenPrice / 100) * tokens;

                tokensDevRewarded = tokensDevRewarded + tokens;
                _addClaimableBalance(dev, amount);
            }

            if(tokensDevRewarded == OFP(ofp).maxTotalSupply()){
                _setNextStep();
            }
            
            
        } else if(currentStep == 11){
            
            require(tempLock, "Request first");
            
            _setNextStep();
            tempLock = false;

            //initiate dev claim locked reward.
            devRewardStart = block.timestamp;
            lastDevRewardClaimDate = block.timestamp;
            devRewardEnd = (block.timestamp + (devRewardDurationMinutes * 1 minutes));

            _addClaimableBalance(dev, (tokenPrice * 400));
            
        }
        
    }
    
    function claimDevSecondReward() auth external {

        require(currentStep > 10, Not_Time_Error);
        require(secondMinutesRewarded < secondRewardDurationMinutes, "reward finish");

        (uint amount, uint pendingMinutes) = pendingSecondReward();

        require(amount > 0, "no claimable reward");

        secondRewardLastClaim = block.timestamp;
        secondMinutesRewarded = secondMinutesRewarded + pendingMinutes;
        _safeTransfer(usdToken, dev, amount);
    }

    function claimDevUtilityReward() external auth {

        require(currentStep > 11, Not_Time_Error);
        require(minutesRewarded < devRewardDurationMinutes, "dev reward finish");

        (uint amount, uint pendingMinutes) = pendingDevReward();

        require(amount > 0, "no claimable reward");
        
        lastDevRewardClaimDate = block.timestamp;
        minutesRewarded = minutesRewarded + pendingMinutes;
        _safeTransfer(utilityToken, dev, amount);

    }
    
    //Raffles

    //Chainlink VRF
    //https://docs.chain.link/vrf/v2/introduction
    //0
    
    function requestRandomWords() external auth emergency {
        require(currentStep == 1 , Not_Time_Error);
        require(vrfRequestId == 0, "The seed was already requested");
        // Will revert if subscription is not set and funded.
        vrfRequestId = VRF_COORDINATOR.requestRandomWords(
            vrfKeyHash,
            vrfSubscriptionId,
            vrfRequestConfirmations,
            vrfCallbackGasLimit,
            vrfNumWords
        );
        
        
    }

    //Raffle
    //0
    function selectTokens() external auth emergency {
        
        require(currentStep >= 2 && currentStep <= 8, Not_Time_Error);
        require(!selectedNextTokens, "tokens already selected");
        
        selectedTokens[ongoingRaffle] = expand(vrfRandomWords[ongoingRaffle], raffleParticipantsNumber[ongoingRaffle], OFP(ofp).maxTotalSupply());
        selectedNextTokens = true;
        
    }
    //1
    function distribute() external auth emergency {
        
        require(currentStep >= 2 && currentStep <= 8, Not_Time_Error);
        require(selectedNextTokens, "First select token ids");
        
        uint[] memory tokens = selectedTokens[ongoingRaffle];

        uint current = 0;
        
        while(current < tokens.length) {
            
            tokenIdRewarded[tokens[current]] = true;
            
            address tokenOwner = OFP(ofp).ownerOf(tokens[current]);
            
            winnerInfo memory w;
            w.IDToken = tokens[current];
            w.owner = tokenOwner;
            
            raffleResult[ongoingRaffle][current] = w;
            
            _addClaimableBalance(tokenOwner, raffleAmounts[ongoingRaffle]);
            
            current++;
            
        }
    
        _setNextStep();
        selectedNextTokens = false;
        ongoingRaffle += 1;
    }

    function communityRaffle(winnerInfo[] memory selectedCommunityMembers) external  gov emergency {
        
        require(currentStep == 9 , Not_Time_Error);
        require(selectedCommunityMembers.length == raffleParticipantsNumber[7], "invalid length");
        _setNextStep();

        for (uint256 index = 0; index < selectedCommunityMembers.length; index++) {

            raffleResult[ongoingRaffle][index] = selectedCommunityMembers[index];
            _addClaimableBalance(selectedCommunityMembers[index].owner, raffleAmounts[ongoingRaffle]);
        }
    }
}   
//interfaces

interface Erc20 {
    function balanceOf(address) view external returns(uint);
    function decimals() view external returns(uint8);
}

interface OFP {
    function maxTotalSupply() view external returns(uint);
    function totalSupply() view external returns(uint);
    function ownerOf(uint) view external returns(address);

    function mint(address, uint) external;
    function burn(uint) external;
    function update() external;

    function balanceOf(address) view external returns(uint);
}

interface UtilityToken {
    function setMinter(address minter_) external;
}

interface Governor {
    function hasActiveProposals() external view returns (bool);
}
