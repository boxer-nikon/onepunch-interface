import { useState, useEffect } from "react";
import { useWeb3React } from "@web3-react/core";
import { formatEther } from "@ethersproject/units";
import type { Web3Provider } from '@ethersproject/providers'

export const Swap = () => {
  const [balance, setBalance] = useState("0");
  const { active, account, library, chainId } = useWeb3React<Web3Provider>();

  useEffect(() => {
    if (active && library && account) {
      library.getBalance(account).then((rs) => {
        setBalance(formatEther(rs));
      });
    }
  }, [active, library, account]);

  return (
    <div className="container">
      <div>ChainId: {chainId}</div>
      <div>Account: {account}</div>
      <div>Balance: {balance} BNB</div>
    </div>
  );
};
