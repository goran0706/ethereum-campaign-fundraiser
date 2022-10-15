// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./CampaignFundraiser.sol";

contract CampaignRegistry {
    address[] public deployedCampaigns;

    function createCampaign(
        uint256 _startsAt,
        uint256 _endsAt,
        uint256 _minFundingGoal,
        uint256 _minContribution,
        uint256 _minReviewsRequired,
        address _manager,
        address _reviewer
    ) public {
        CampaignFundraiser newCampaign = new CampaignFundraiser(
            _startsAt,
            _endsAt,
            _minFundingGoal,
            _minContribution,
            _minReviewsRequired,
            _manager,
            _reviewer
        );
        deployedCampaigns.push(address(newCampaign));
    }

    function getDeployedCampaigns() public view returns (address[] memory) {
        return deployedCampaigns;
    }
}
