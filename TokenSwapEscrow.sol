// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract TokenSwapEscrow is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    
    Counters.Counter private _escrowIdCounter;
    
    struct TokenAmount {
        address tokenAddress;
        uint256 amount;
    }
    
    struct EscrowData {
        uint256 escrowId;
        address party1;
        address party2;
        TokenAmount[] inputTokens;  // Tokens party1 deposits
        TokenAmount[] outputTokens; // Tokens party2 deposits
        uint256 deadline;
        EscrowStatus status;
        bool party1Deposited;
        bool party2Deposited;
        bool party1Approved;
        bool party2Approved;
        uint256 createdAt;
        uint256 disputeDeadline;
    }
    
    enum EscrowStatus {
        Created,
        Active,
        Completed,
        Cancelled,
        Disputed,
        Expired
    }
    
    // Mappings
    mapping(uint256 => EscrowData) public escrows;
    mapping(uint256 => mapping(address => bool)) public hasDeposited;
    mapping(address => uint256[]) public userEscrows;
    
    // Constants
    uint256 public constant MIN_ESCROW_DURATION = 1 hours;
    uint256 public constant MAX_ESCROW_DURATION = 30 days;
    uint256 public constant DISPUTE_PERIOD = 7 days;
    uint256 public constant MAX_TOKENS_PER_SIDE = 10;
    
    // Fee structure
    uint256 public escrowFeePercent = 25; // 0.25% (25/10000)
    uint256 public constant FEE_DENOMINATOR = 10000;
    address public feeRecipient;
    
    // Events
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed party1,
        address indexed party2,
        uint256 deadline
    );
    
    event TokensDeposited(
        uint256 indexed escrowId,
        address indexed depositor,
        TokenAmount[] tokens
    );
    
    event EscrowApproved(
        uint256 indexed escrowId,
        address indexed approver
    );
    
    event EscrowCompleted(
        uint256 indexed escrowId,
        address indexed party1,
        address indexed party2
    );
    
    event EscrowCancelled(
        uint256 indexed escrowId,
        address indexed canceller
    );
    
    event DisputeRaised(
        uint256 indexed escrowId,
        address indexed disputer
    );
    
    event DisputeResolved(
        uint256 indexed escrowId,
        address indexed resolver,
        bool party1Wins
    );
    
    event EmergencyWithdraw(
        uint256 indexed escrowId,
        address indexed user,
        TokenAmount[] tokens
    );
    
    // Modifiers
    modifier validEscrow(uint256 _escrowId) {
        require(_escrowId < _escrowIdCounter.current(), "Invalid escrow ID");
        _;
    }
    
    modifier onlyParties(uint256 _escrowId) {
        EscrowData storage escrow = escrows[_escrowId];
        require(
            msg.sender == escrow.party1 || msg.sender == escrow.party2,
            "Not authorized"
        );
        _;
    }
    
    modifier escrowActive(uint256 _escrowId) {
        require(
            escrows[_escrowId].status == EscrowStatus.Active ||
            escrows[_escrowId].status == EscrowStatus.Created,
            "Escrow not active"
        );
        _;
    }
    
    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient != address(0) ? _feeRecipient : msg.sender;
    }
    
    /**
     * @dev Create a new escrow between two parties
     */
    function createEscrow(
        address _party2,
        TokenAmount[] calldata _inputTokens,
        TokenAmount[] calldata _outputTokens,
        uint256 _duration
    ) external whenNotPaused nonReentrant returns (uint256) {
        require(_party2 != address(0) && _party2 != msg.sender, "Invalid party2");
        require(
            _duration >= MIN_ESCROW_DURATION && _duration <= MAX_ESCROW_DURATION,
            "Invalid duration"
        );
        require(
            _inputTokens.length > 0 && _inputTokens.length <= MAX_TOKENS_PER_SIDE,
            "Invalid input tokens"
        );
        require(
            _outputTokens.length > 0 && _outputTokens.length <= MAX_TOKENS_PER_SIDE,
            "Invalid output tokens"
        );
        
        uint256 escrowId = _escrowIdCounter.current();
        _escrowIdCounter.increment();
        
        EscrowData storage newEscrow = escrows[escrowId];
        newEscrow.escrowId = escrowId;
        newEscrow.party1 = msg.sender;
        newEscrow.party2 = _party2;
        newEscrow.deadline = block.timestamp + _duration;
        newEscrow.status = EscrowStatus.Created;
        newEscrow.createdAt = block.timestamp;
        
        // Store tokens
        for (uint256 i = 0; i < _inputTokens.length; i++) {
            require(_inputTokens[i].tokenAddress != address(0), "Invalid token address");
            require(_inputTokens[i].amount > 0, "Invalid token amount");
            newEscrow.inputTokens.push(_inputTokens[i]);
        }
        
        for (uint256 i = 0; i < _outputTokens.length; i++) {
            require(_outputTokens[i].tokenAddress != address(0), "Invalid token address");
            require(_outputTokens[i].amount > 0, "Invalid token amount");
            newEscrow.outputTokens.push(_outputTokens[i]);
        }
        
        userEscrows[msg.sender].push(escrowId);
        userEscrows[_party2].push(escrowId);
        
        emit EscrowCreated(escrowId, msg.sender, _party2, newEscrow.deadline);
        
        return escrowId;
    }
    
    /**
     * @dev Deposit tokens into the escrow
     */
    function depositTokens(uint256 _escrowId) 
        external 
        validEscrow(_escrowId)
        onlyParties(_escrowId)
        escrowActive(_escrowId)
        nonReentrant 
    {
        EscrowData storage escrow = escrows[_escrowId];
        require(block.timestamp < escrow.deadline, "Escrow expired");
        
        TokenAmount[] memory tokensToDeposit;
        bool isParty1 = msg.sender == escrow.party1;
        
        if (isParty1) {
            require(!escrow.party1Deposited, "Already deposited");
            tokensToDeposit = escrow.inputTokens;
            escrow.party1Deposited = true;
        } else {
            require(!escrow.party2Deposited, "Already deposited");
            tokensToDeposit = escrow.outputTokens;
            escrow.party2Deposited = true;
        }
        
        // Transfer tokens
        for (uint256 i = 0; i < tokensToDeposit.length; i++) {
            IERC20(tokensToDeposit[i].tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokensToDeposited[i].amount
            );
        }
        
        hasDeposited[_escrowId][msg.sender] = true;
        
        if (escrow.party1Deposited && escrow.party2Deposited) {
            escrow.status = EscrowStatus.Active;
        }
        
        emit TokensDeposited(_escrowId, msg.sender, tokensToDeposit);
    }
    
    /**
     * @dev Approve the escrow completion
     */
    function approveEscrow(uint256 _escrowId)
        external
        validEscrow(_escrowId)
        onlyParties(_escrowId)
        nonReentrant
    {
        EscrowData storage escrow = escrows[_escrowId];
        require(escrow.status == EscrowStatus.Active, "Escrow not active");
        require(block.timestamp < escrow.deadline, "Escrow expired");
        
        if (msg.sender == escrow.party1) {
            escrow.party1Approved = true;
        } else {
            escrow.party2Approved = true;
        }
        
        emit EscrowApproved(_escrowId, msg.sender);
        
        if (escrow.party1Approved && escrow.party2Approved) {
            _completeEscrow(_escrowId);
        }
    }
    
    /**
     * @dev Complete the escrow and transfer tokens
     */
    function _completeEscrow(uint256 _escrowId) internal {
        EscrowData storage escrow = escrows[_escrowId];
        escrow.status = EscrowStatus.Completed;
        
        // Transfer tokens with fees
        for (uint256 i = 0; i < escrow.inputTokens.length; i++) {
            TokenAmount memory token = escrow.inputTokens[i];
            uint256 fee = (token.amount * escrowFeePercent) / FEE_DENOMINATOR;
            uint256 transferAmount = token.amount - fee;
            
            if (fee > 0) {
                IERC20(token.tokenAddress).safeTransfer(feeRecipient, fee);
            }
            IERC20(token.tokenAddress).safeTransfer(escrow.party2, transferAmount);
        }
        
        for (uint256 i = 0; i < escrow.outputTokens.length; i++) {
            TokenAmount memory token = escrow.outputTokens[i];
            uint256 fee = (token.amount * escrowFeePercent) / FEE_DENOMINATOR;
            uint256 transferAmount = token.amount - fee;
            
            if (fee > 0) {
                IERC20(token.tokenAddress).safeTransfer(feeRecipient, fee);
            }
            IERC20(token.tokenAddress).safeTransfer(escrow.party1, transferAmount);
        }
        
        emit EscrowCompleted(_escrowId, escrow.party1, escrow.party2);
    }
    
    // Additional functions for cancellation, disputes, etc...
    // [Rest of the contract code continues with similar patterns]
}


