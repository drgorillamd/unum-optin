# unum-optin
Provide a solution to manage cdao2 NFT holder opt-ining to unumDAO (while automating cdao2 redemption).


This contract will, sequentially:
- Pull the CDAO2 NFT
- Approve the terminal
- Redeem the CDAO2 NFT for ETH
- Use the ETH received to contribute to Unum project, while sending Unum NFT to the msg.sender

If the CDAO2 treasury has some "extra" eth (ie treasury % sum of floors != 0), they extra share is sent without minting (as a result,
if all CDAO2 were to used to opt-in, the whole CDAO2 treasury would be transfered)
