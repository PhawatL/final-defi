// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;
import "./CommitReveal.sol";
import "./TimeUnit.sol";
import "./IERC20.sol";

contract RPSCommitReveal {
    uint256 public numPlayer = 0;
    uint256 public reward = 0;
    address[] private players;
    uint256 private constant REQUIRED_AMOUNT = 0.000001 ether;

    // ERC20 token contract
    IERC20 public tokenContract;

    CommitReveal public cr = new CommitReveal();
    TimeUnit public afterStartTimeUnit = new TimeUnit();
    TimeUnit public afterCommitTimeUnit = new TimeUnit();

    mapping(address => bytes32) public playerChoice;
    mapping(address => bool) public isPlayed;
    mapping(address => bool) public hasPaid;

    mapping(uint256 => uint256) private transform;
    uint256 public numInput = 0;
    uint256 public numReveal;

    constructor(address _tokenAddress) {
        afterStartTimeUnit.setStartTime();
        tokenContract = IERC20(_tokenAddress);

        transform[2] = 0;
        transform[0] = 1;
        transform[3] = 2;
        transform[1] = 3;
        transform[4] = 4;
    }

    function getPlayers() public view returns (address[] memory) {
        return players;
    }

    function addPlayer() public {
        require(numPlayer < 2, "Only two players allowed");
        if (numPlayer > 0) {
            require(msg.sender != players[0], "Player already joined");
        }
        
        // Check if player has approved the contract to withdraw REQUIRED_AMOUNT
        uint256 allowedAmount = tokenContract.allowance(msg.sender, address(this));
        console.log(allowedAmount);
        require(allowedAmount >= REQUIRED_AMOUNT, "Must approve contract to withdraw 0.000001 ether");
        
        players.push(msg.sender);

        if (numPlayer == 0) {
            afterStartTimeUnit.setStartTime();
        }
        if (numPlayer == 1) {
            afterStartTimeUnit.setStartTime();
        }

        numPlayer++;
    }

    function commitChoice(bytes32 digest) public {
        require(!isPlayed[msg.sender], "Player already choosed");
        require(
            msg.sender == players[0] || msg.sender == players[1],
            "Player does not match"
        );

        cr.commit(msg.sender, digest);
        isPlayed[msg.sender] = true;
        numInput++;
        
        if (numInput == 2) {
            afterCommitTimeUnit.setStartTime();
            
            // Transfer tokens from both players to the contract when both have committed
            for (uint256 i = 0; i < players.length; i++) {
                bool success = _safeTransferFrom(tokenContract, players[i], address(this), REQUIRED_AMOUNT);
                require(success, "Transfer failed");
                hasPaid[players[i]] = true;
            }
            
            reward = REQUIRED_AMOUNT * 2;
        }
    }

    // Helper function for safe token transfer
    function _safeTransferFrom(
        IERC20 token,
        address sender,
        address recipient,
        uint256 amount
    ) private returns (bool) {
        bool sent = token.transferFrom(sender, recipient, amount);
        return sent;
    }

    // ส่ง ข้อมูลตัั้งต้นก่อนเข้า hash function เข้ามา หรือก็คือ random byte 31 bytes concat กับ choice ที่เลือก 1 byte
    function revealChoice(bytes32 encodedData) public {
        require(numInput == 2, "Not all players committed");
        cr.reveal(msg.sender, encodedData);

        numReveal++;
        playerChoice[msg.sender] = encodedData;
        if (numReveal == 2) {
            _checkWinnerAndPay();
        }
    }

    function _checkWinnerAndPay() private {
        bytes32 p0EncodedChoice = playerChoice[players[0]];
        bytes32 p1EncodedChoice = playerChoice[players[1]];

        // get last byte of each bytes32 value and convert to int
        bytes1 lastByte = p0EncodedChoice[31];
        uint8 value = uint8(lastByte);
        uint256 p0Choice = uint256(value);

        bytes1 lastByteP1 = p1EncodedChoice[31];
        uint8 valueP1 = uint8(lastByteP1);
        uint256 p1Choice = uint256(valueP1);

        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);

        if (abs(int256(p0Choice), int256(p1Choice)) != 1) {
            p0Choice = transform[p0Choice];
            p1Choice = transform[p1Choice];
        }

        if ((p0Choice + 1) % 5 == p1Choice) {
            tokenContract.transfer(account0, reward);
        } else if ((p1Choice + 1) % 5 == p0Choice) {
            tokenContract.transfer(account1, reward);
        } else {
            // กรณีเสมอ
            tokenContract.transfer(account0, reward / 2);
            tokenContract.transfer(account1, reward / 2);
        }

        // reset game
        _reset();
    }

    function uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint256 j = v;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        while (v != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(v % 10));
            bstr[k] = bytes1(temp);
            v /= 10;
        }
        return string(bstr);
    }

function withdrawnMoney() public {
    require(numPlayer > 0, "Not enough players");
    uint256 elapsed = afterStartTimeUnit.elapsedSeconds();
    
    // ประกาศ account0 ไว้ก่อนใช้งาน
    address payable account0 = payable(players[0]);

    if (players.length == 1) {
        // Case 1: ผู้เล่นเดียวรอเข้าร่วม
        require(
            elapsed > 20,
            string(
                abi.encodePacked(
                    "Elapsed time: ",
                    uintToString(elapsed),
                    " seconds. Please wait until 20 seconds. (Single player waiting)"
                )
            )
        );

        tokenContract.transfer(account0, tokenContract.balanceOf(address(this)));
        _reset();
        return;
    }

    // Case 2: มีผู้เล่นครบ 2 คน แต่ยังไม่ได้ commit ทั้งหมด
    require(
        elapsed > 60,
        string(
            abi.encodePacked(
                "Elapsed time: ",
                uintToString(elapsed),
                " seconds. Please wait until 60 seconds. (Both players have joined, but not all have committed)"
            )
        )
    );
    
    // ประกาศ account1 สำหรับผู้เล่นคนที่สอง
    address payable account1 = payable(players[1]);
    
    if (!isPlayed[players[0]] && !isPlayed[players[1]]) {
        // ไม่มีผู้เล่น commit
        if (hasPaid[players[0]] && hasPaid[players[1]]) {
            uint256 contractBalance = tokenContract.balanceOf(address(this));
            tokenContract.transfer(account0, contractBalance / 2);
            tokenContract.transfer(account1, contractBalance / 2);
        }
    } else if (isPlayed[players[0]] && !isPlayed[players[1]]) {
        // มีแค่ผู้เล่น 0 commit
        tokenContract.transfer(account0, tokenContract.balanceOf(address(this)));
    } else if (!isPlayed[players[0]] && isPlayed[players[1]]) {
        // มีแค่ผู้เล่น 1 commit
        tokenContract.transfer(account1, tokenContract.balanceOf(address(this)));
    } else {
        // Case 3: ทั้งคู่ commit แล้วแต่ไม่ reveal
        elapsed = afterCommitTimeUnit.elapsedSeconds();
        require(
            elapsed > 30,
            string(
                abi.encodePacked(
                    "Elapsed time: ",
                    uintToString(elapsed),
                    " seconds. Please wait until 30 seconds after last player commit."
                )
            )
        );
        
        if (numReveal == 0) {
            // ไม่มีผู้เล่น reveal - ใครเรียกก็สามารถถอนได้ทั้งหมด
            address payable withdrawer = payable(msg.sender);
            tokenContract.transfer(withdrawer, tokenContract.balanceOf(address(this)));
        } else if (playerChoice[players[0]] != bytes32(0)) {
            // มีแค่ผู้เล่น 0 reveal
            tokenContract.transfer(account0, tokenContract.balanceOf(address(this)));
        } else {
            // มีแค่ผู้เล่น 1 reveal
            tokenContract.transfer(account1, tokenContract.balanceOf(address(this)));
        }
    }
    _reset();
}


    function _reset() private {
        // Clear CommitReveal data
        for (uint256 i = 0; i < players.length; i++) {
            cr.resetPlayer(players[i]);
        }

        // Clear game state
        for (uint256 i = 0; i < players.length; i++) {
            address player = players[i];
            delete isPlayed[player];
            delete playerChoice[player];
            delete hasPaid[player];
        }
        delete players;

        numInput = 0;
        numReveal = 0;
        numPlayer = 0;
        reward = 0;
    }

    function abs(int256 x, int256 y) private pure returns (int256) {
        return (x - y) >= 0 ? (x - y) : -(x - y);
    }

    function getHash(bytes32 data) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(data));
    }
}