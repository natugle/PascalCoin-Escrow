PascalCoin Escrow

{ Copyright (c) 2018 by Preben Björn Biermann Madsen
  email: prebenbjornmadsen@gmail.com
  http://pascalcoin.frizen.eu

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

  This is a part of the Pascal Coin Project.

  If you like it, consider a donation using Pascal Coin Account: 274800-71
}

PascalCoin Escrow is an example to show how an Ecrow Service for PascalCoin can be developed. 
Warning: The program needs a lot more error checking and debugging.

It uses the Payload so all PascalCoin account holders can communicate manually from the wallet to the Escrow Service.


How to use


Deposit an amount
-----------------
Users send an ammount to the escrow service account with an uncoded payload text: escrow 1-22 

1-22 is the receivers account number.
The deposit is saved in the Escrow service data base until new commands are send. The ophash of the operation is used to identify the deposit.


Forward a deposit to the receiver
-----------------------------
Initiating User sends 0.0001 Pasc to the escrow service account with an uncoded payload text: forward DF5102004AB601000D000000B03277F28E07C93C6E3B7563736D650CBE0A81A8

DF51.... is the ophash of the deposit operation
The escrow sends the deposit minus a fee to the receiver.
This is how the sender should release the deposit to the receiver when she or he have done hers or his part of the deal.



Return a deposit to Initiating User
-----------------------------------
Initiating User sends 0.0001 Pasc to the escrow service account with an uncoded payload text: return DF5102004AB601000D000000B03277F28E07C93C6E3B7563736D650CBE0A81A8  

DF51.... is the ophash of the deposit operation
The escrow sends the deposit minus a fee back to the Initiating User. This command should first be executed after a number of blocks (here 300 blocks - around 24 hour)
This is the senders way to get the deposit back if the receiver doesn't respond.



Lock the deposit
----------------
The intended receiver sends 0.0001 Pasc  to the escrow service account with an uncoded payload text: lock DF5102004AB601000D000000B03277F28E07C93C6E3B7563736D650CBE0A81A8

DF51.... is the ophash of the deposit operation
The Escrow then Lock or freeze the deposit and send messages to both of the involved parties.
This is the receivers way to freeze the deposit so it can't be returned, if the sender doesn't forward the deposit. The Escrow freeze the deposit until the disput has been solved.


