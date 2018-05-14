pragma solidity ^0.4.13;
contract ERC20 {
    function transfer(address _to, uint _value) public returns (bool success);
}
contract microLending{
    address public owner;
    enum ProposalState {
        WAITING,
        ACCEPTED,
        REPAID,
        TOKENISED,
        LOST
    }
    
    struct Proposal {
        address lender;
        uint loanId;
        ProposalState state;
        uint interestRate;
        uint amount;
    }
    enum LoanState {
        ACCEPTING,
        LOCKED,
        SUCCESSFUL,
        FAILED
    }
    enum TokenState{
        UNUSED,
        USED
    }
    struct TokenHoldings{
        address tokenAddress;
        uint tokensHolding;
        address txId;
        TokenState state;
    }
    struct Loan {
        address borrower;
        LoanState state;
        uint dueDate;
        uint amount;
        uint proposalCount;
        uint collected;
        uint startDate;
        bool tokenSecurity;
        mapping (uint=>uint) tokens;
        mapping (uint=>uint) proposal;
    }
    Loan[] public loans;
    Proposal[] public proposals;
    TokenHoldings[] public tokens;
    mapping(address=>int) public Reputation;
    mapping(address =>uint[]) public loansmap;
    mapping(address =>uint[]) public proposalsmap;
    mapping(uint => uint[]) tokensmap;
    function hasActiveLoan(address borrower) constant public returns(bool) {
        uint activeLoans = loansmap[borrower].length;
        if(activeLoans == 0){
           return false;
        }
        if(loans[activeLoans-1].state == LoanState.ACCEPTING) {
            return true;
        }
        if(loans[activeLoans-1].state == LoanState.LOCKED){
            return true;
        }
        return false;
    }
    //Request Loan with Tokens as security risk
    function newLoanWithTokens(uint amount, uint dueDate,address tokenAddress,uint tokensHoldings,address txId) public {
        if(hasActiveLoan(msg.sender)) {
            return;
        }
        uint currentDate = block.timestamp;
        uint due = currentDate + dueDate*1 minutes;
        loans.push(Loan(msg.sender, LoanState.ACCEPTING, due, amount*1 ether, 0, 0, currentDate,true));
        tokens.push(TokenHoldings(tokenAddress,tokensHoldings,txId,TokenState.UNUSED)); 
        loans[loans.length-1].tokens[0] = tokens.length-1;
        loansmap[msg.sender].push(loans.length-1);
    }
    //Request Loan with out any security , Lenders will see the Reputation of the Borrower and take the risk
    function newLoan(uint amount, uint dueDate) public {
        if(hasActiveLoan(msg.sender)) {
            return;
        }
        uint currentDate = block.timestamp;
        uint due = currentDate + dueDate*1 minutes;
        loans.push(Loan(msg.sender, LoanState.ACCEPTING, due, amount*1 ether,0, 0, currentDate,false));
        loansmap[msg.sender].push(loans.length-1);
    }
    //Lenders Proposal to the Loan 
    function newProposal(uint loanId, uint rate) public payable {
        if(loans[loanId].borrower == 0 || loans[loanId].state != LoanState.ACCEPTING)
            return;
        proposals.push(Proposal(msg.sender, loanId, ProposalState.WAITING, rate, msg.value));
        proposalsmap[msg.sender].push(proposals.length-1);
        loans[loanId].proposalCount++;
        loans[loanId].proposal[loans[loanId].proposalCount-1] = proposals.length-1;
    }
    modifier loanOwner(uint loanid){
        if(loans[loanid].borrower == msg.sender){
            _;
        }
        else{
            require(loans[loanid].borrower == msg.sender);
        }
    }
    //Returns the Last Active Loan ID
    function getLastLoanId(address borrower) public constant returns(uint){
        uint numLoans = loansmap[borrower].length;
        if(numLoans == 0) return (2**64 - 1);
        uint lastLoanId = loansmap[borrower][numLoans-1];
        if(loans[lastLoanId].state != LoanState.ACCEPTING) return (2**64 - 1);
        return lastLoanId;
    }
    function acceptProposal(uint proposeId) public {
        uint loanId = getLastLoanId(msg.sender); 
        if(loanId == (2**64 - 1)) return;
        if(loans[loanId].dueDate < now) require(loans[loanId].dueDate > now);
        Proposal storage pObj = proposals[proposeId];
        if(pObj.state != ProposalState.WAITING) return;

        Loan storage lObj = loans[loanId];
        if(lObj.state != LoanState.ACCEPTING) return;

        if(lObj.collected + pObj.amount <= lObj.amount)
        {
          loans[loanId].collected += pObj.amount;
          proposals[proposeId].state = ProposalState.ACCEPTED;
          //Reputation[proposals[accPropId].lender] = Reputation[proposals[accPropId].lender]+int(proposals[accPropId].amount/(0.1 ether));
        }
    }
    //Borrower accepts the Loan Proposals 
    event LoanLocked(uint loanId);
    function lockLoan() public {
        uint count = 0;
        uint loanId = getLastLoanId(msg.sender);
        if(loanId == (2**64 - 1)) return;
        if(loans[loanId].state != LoanState.ACCEPTING){
            require(loans[loanId].state == LoanState.ACCEPTING);
        }
        loans[loanId].state = LoanState.LOCKED;
        for(uint i = 0; i < loans[loanId].proposalCount; i++) {
            uint accPropId = loans[loanId].proposal[i];
            if(proposals[accPropId].state == ProposalState.ACCEPTED)
            {
              msg.sender.transfer(proposals[accPropId].amount); //Send to borrower
              Reputation[proposals[accPropId].lender] += int(proposals[accPropId].amount/(0.1 ether));
              count++;
            }
            else
            {
              proposals[accPropId].state = ProposalState.REPAID;
              proposals[accPropId].lender.transfer(proposals[accPropId].amount); //Send back to lender
            }
        }
        if(count==0){
            loans[loanId].state = LoanState.FAILED;
        }else{
             LoanLocked(loanId);   
        }
    }
    event RevokedAmount(uint loanid,address lender,uint amount);
    event RevokedTokens(uint loanid,address lender,address tokenAddress,uint tokens);
    // Lenders Revoke the Proposal only if its not ACCEPTED or deadline exceeded
    function revokeProposal(uint id) public{
        uint proposeId = proposalsmap[msg.sender][id];
        uint loanId = proposals[proposeId].loanId;
        require(proposals[proposeId].state != ProposalState.TOKENISED);
        require(proposals[proposeId].state != ProposalState.LOST);
        require(loans[loanId].state != LoanState.FAILED);
        require(proposals[proposeId].state != ProposalState.REPAID);
        if(loans[loanId].state == LoanState.ACCEPTING) {
            proposals[proposeId].state = ProposalState.REPAID;
            msg.sender.transfer(proposals[proposeId].amount);
            RevokedAmount(loanId,proposals[proposeId].lender,proposals[proposeId].amount);
        }
        else if(loans[loanId].state == LoanState.LOCKED) {
            if(loans[loanId].dueDate > now) return;
            loans[loanId].state = LoanState.FAILED;
            if(loans[loanId].tokenSecurity == false){
                for(uint k = 0; k < loans[loanId].proposalCount; k++) {
                    uint pid = loans[loanId].proposal[k];
                    if(proposals[pid].state == ProposalState.ACCEPTED) {
                        uint loanPercent = ((proposals[pid].amount*100)/loans[loanId].collected);
                        Reputation[proposals[pid].lender] += int((Reputation[loans[loanId].borrower]*int(loanPercent))/100);
                    }
                }
                Reputation[loans[loanId].borrower] = 0; 
                Reputation[loans[loanId].borrower] -= int(loans[loanId].collected/(0.1 * 1 ether));
            }else{
                Reputation[loans[loanId].borrower] -= int(loans[loanId].collected/(0.1 * 1 ether));
                uint tokenID = loans[loanId].tokens[0];
                uint tokenHoldings = tokens[tokenID].tokensHolding;
                address tokenAddress = tokens[tokenID].tokenAddress;
                if(tokens[tokenID].state == TokenState.USED) return;
                for(uint i = 0; i < loans[loanId].proposalCount; i++) {
                    uint numI = loans[loanId].proposal[i];
                    if(proposals[numI].state == ProposalState.ACCEPTED) {
                        uint loanP = uint(((proposals[numI].amount*100)/loans[loanId].collected));
                        ERC20 tokenContract = ERC20(tokenAddress);
                        tokenContract.transfer(proposals[numI].lender,uint((tokenHoldings*loanP)/100)); 
                        proposals[numI].state = ProposalState.TOKENISED;
                        RevokedTokens(loans[loanId].amount,proposals[numI].lender,tokenAddress,(tokenHoldings*loanP)/100);
                    }
                }
                tokens[tokenID].state = TokenState.USED;
            }
        }
    }
    // Returns the Loan Repayment Amount 
    function getRepayValue(uint loanId) public constant returns(uint) {
        if(loans[loanId].state == LoanState.LOCKED)
        {
          uint time = loans[loanId].startDate;
          uint finalamount = 0;
          for(uint i = 0; i < loans[loanId].proposalCount; i++)
          {
            uint numI = loans[loanId].proposal[i];
            if(proposals[numI].state == ProposalState.ACCEPTED)
            {
              uint original = proposals[numI].amount;
              uint rate = proposals[numI].interestRate;
              uint currentTime = block.timestamp;
              uint interest = (original*rate*(currentTime - time))/(365*24*60*60*100);
              finalamount += interest;
              finalamount += original;
            }
          }
          return finalamount;
        }
        else
          return (2**64 -1);
    }
    //Borower pays the Loan with interest
    function payLoan(uint loanId) payable public{
        uint finalAmount = getRepayValue(loanId);
        if(finalAmount == (2**64 -1)){
            msg.sender.transfer(msg.value);
            return; 
        }
        if(loans[loanId].state != LoanState.LOCKED ){
            msg.sender.transfer(msg.value);
            return;  
        } 
        if(loans[loanId].dueDate < now){
            msg.sender.transfer(msg.value);
            return;
        }
        uint time = loans[loanId].startDate;
        uint paid = msg.value;
        uint remain = paid;

        if(paid >= finalAmount){
            for(uint i=0;i<loans[loanId].proposalCount;i++){
                uint id = loans[loanId].proposal[i];
                if(proposals[id].state == ProposalState.ACCEPTED){
                    uint original = proposals[id].amount;
                    uint rate = proposals[id].interestRate;
                    uint interest = (original*rate*(now - time))/(365*24*60*60*100);
                    uint amountToPay = interest + original;
                    proposals[id].lender.transfer(amountToPay);
                    proposals[id].state = ProposalState.REPAID;
                    remain = remain-amountToPay;
                }
            }
            loans[loanId].state = LoanState.SUCCESSFUL;
            msg.sender.transfer(remain);
            if(loans[loanId].tokenSecurity){
                uint tokenid = loans[loanId].tokens[0];
                ERC20 tokenContract = ERC20(tokens[tokenid].tokenAddress);
                tokenContract.transfer(msg.sender,tokens[tokenid].tokensHolding);
                tokens[tokenid].state = TokenState.USED;
            }
            Reputation[msg.sender] = Reputation[msg.sender]+int(finalAmount/(0.1 ether));
        }else{
            msg.sender.transfer(paid);
        }
    }
}
