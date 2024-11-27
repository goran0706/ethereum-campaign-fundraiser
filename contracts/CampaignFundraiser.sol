// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/PullPayment.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CampaignFundraiser is AccessControl, PullPayment, ReentrancyGuard {
    uint256 public startsAt;
    uint256 public endsAt;
    uint256 public weiRaised;
    uint256 public weiRefunded;
    uint256 public weiSpent;
    uint256 public weiPendingBalance;
    uint256 public minFundingGoal;
    uint256 public minContribution;
    uint256 public minReviewsRequired;
    uint256 public contributorsCount;
    uint256 public spendingRequestsCount;

    bytes32 private constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 private constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    mapping(address => uint256) public contributors;
    mapping(uint256 => Request) public requests;

    enum RequestStatus {
        PENDING,
        REJECTED,
        APPROVED,
        COMPLETED
    }

    struct Request {
        string description;
        address recipient;
        uint256 value;
        uint256 approvalsCount;
        uint256 rejectionsCount;
        RequestStatus status;
        mapping(address => bool) reviews;
    }

    event Contribute(address indexed contributor, uint256 value, uint256 timestamp);
    event Refund(address indexed contributor, uint256 value, uint256 timestamp);
    event SpendingRequest(
        string description,
        address recipient,
        uint256 value,
        uint256 approvalsCount,
        uint256 rejectionsCount,
        RequestStatus status
    );

    constructor(
        uint256 _startsAt,
        uint256 _endsAt,
        uint256 _minFundingGoal,
        uint256 _minContribution,
        uint256 _minReviewsRequired,
        address _manager,
        address _reviewer
    ) {
        startsAt = _startsAt;
        endsAt = _endsAt;
        minFundingGoal = _minFundingGoal;
        minContribution = _minContribution;
        minReviewsRequired = _minReviewsRequired;

        _setupRole(MANAGER_ROLE, _manager);
        _setupRole(REVIEWER_ROLE, _reviewer);
    }

    function contribute(uint256 value) public payable {
        uint256 timestamp = block.timestamp;
        require(timestamp > startsAt, "Campaign has not started yet");
        require(timestamp < endsAt, "Campaign has already ended");
        require(value == msg.value, "Value sent doesn't match the value");
        require(value >= minContribution, "Minimum contribution not met");

        address contributor = msg.sender;

        if (contributors[contributor] == 0) {
            contributorsCount++;
        }

        weiRaised += value;
        contributors[contributor] += value;

        emit Contribute(contributor, value, timestamp);
    }

    function refund() public nonReentrant {
        uint256 timestamp = block.timestamp;
        require(timestamp > startsAt, "Campaign has not started yet");
        require(timestamp < endsAt || weiRaised < minFundingGoal, "Refund not allowed");
        address contributor = msg.sender;
        require(contributors[contributor] > 0, "No contribution to refund");

        uint256 value = contributors[contributor];

        weiRefunded += value;
        contributors[contributor] = 0;
        contributorsCount--;

        _asyncTransfer(contributor, value);

        emit Refund(contributor, value, timestamp);
    }

    function finalizeCampaign() public {
        require(block.timestamp > endsAt, "Campaign still in progress");
        weiPendingBalance = address(this).balance;
    }

    function createSpendingRequest(
        string memory _description,
        address _recipient,
        uint256 _value
    ) public {
        require(block.timestamp > endsAt, "Campaign still in progress");
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a manager");
        require(_recipient != address(0), "Recipient cannot be zero address");
        require(_value <= weiPendingBalance, "Insufficient funds");

        Request storage request = requests[spendingRequestsCount++];
        request.description = _description;
        request.recipient = _recipient;
        request.value = _value;
        request.approvalsCount = 0;
        request.rejectionsCount = 0;
        request.status = RequestStatus.PENDING;

        emitSpendingRequest(request);
    }

    function rejectSpendingRequest(uint256 requestKey) public {
        address reviewer = msg.sender;
        require(hasRole(REVIEWER_ROLE, reviewer), "Caller is not a reviewer");

        Request storage request = requests[requestKey];
        require(request.status == RequestStatus.PENDING, "Request not pending");
        require(!request.reviews[reviewer], "Reviewer already voted");

        request.rejectionsCount++;
        request.reviews[reviewer] = true;

        if (request.rejectionsCount >= minReviewsRequired) {
            request.status = RequestStatus.REJECTED;
        }

        emitSpendingRequest(request);
    }

    function acceptSpendingRequest(uint256 requestKey) public {
        address reviewer = msg.sender;
        require(hasRole(REVIEWER_ROLE, reviewer), "Caller is not a reviewer");

        Request storage request = requests[requestKey];
        require(request.status == RequestStatus.PENDING, "Request not pending");
        require(request.value <= weiPendingBalance, "Insufficient pending funds");
        require(!request.reviews[reviewer], "Reviewer already voted");

        request.approvalsCount++;
        request.reviews[reviewer] = true;

        if (request.approvalsCount >= minReviewsRequired) {
            weiPendingBalance -= request.value;
            request.status = RequestStatus.APPROVED;
        }

        emitSpendingRequest(request);
    }

    function completeSpendingRequest(uint256 requestKey) public {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a manager");

        Request storage request = requests[requestKey];
        require(request.status == RequestStatus.APPROVED, "Request not approved");
        require(request.value <= address(this).balance, "Insufficient balance");

        weiSpent += request.value;
        request.status = RequestStatus.COMPLETED;
        _asyncTransfer(request.recipient, request.value);

        emitSpendingRequest(request);
    }

    function emitSpendingRequest(Request storage request) private {
        emit SpendingRequest(
            request.description,
            request.recipient,
            request.value,
            request.approvalsCount,
            request.rejectionsCount,
            request.status
        );
    }
}
