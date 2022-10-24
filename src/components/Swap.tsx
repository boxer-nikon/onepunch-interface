import { ChangeEvent, useState, useEffect, useCallback } from "react";
import { useWeb3React } from "@web3-react/core";
import type { Web3Provider } from "@ethersproject/providers";
import { Contract } from '@ethersproject/contracts';
import { MaxInt256 } from '@ethersproject/constants';
import { Card, Input, Button } from "antd";
import { ArrowDownOutlined } from "@ant-design/icons";

import { getQuotePrice } from "../apis";
import ERC20ABI from '../abis/ERC20.json'
import DexLiquidityProviderABI from '../abis/DexLiquidityProvider.json'

const SWAP_ADDRESS = "0x33FD1461E52Cd19f74d720F72fc9C15063CC6113"

export const Swap = () => {
  const [loading, setLoading] = useState(false)
  const [fromAmount, setFromAmount] = useState("0");
  const [toAmount, setToAmount] = useState("0");
  const { account, library} = useWeb3React<Web3Provider>();

  const handleFromChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setFromAmount(e.currentTarget.value);
  }, []);

  const handleToChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setToAmount(e.currentTarget.value);
  }, []);

  const handleConfirm = useCallback(async () => {
    // 1. get latest quote
    const fromToken = new Contract("",  ERC20ABI)
    // 2. check allowonce
    const allowonce = await fromToken.allowance(account, SWAP_ADDRESS)
    if (!allowonce.gt(fromAmount)) {
      const tx = await fromToken.approve(SWAP_ADDRESS, MaxInt256)
      await tx.wait();
    }
    // 3. call swap contract
    const swapContract = new Contract(SWAP_ADDRESS, DexLiquidityProviderABI, library?.getSigner())
    await swapContract.swapRequest();
  }, [account, fromAmount, library]);

  useEffect(() => {
    if (!account) return;

    setLoading(true)
    getQuotePrice().then(rs =>  {
      console.log("🚀 ~ file: Swap.tsx ~ line 34 ~ getQuotePrice ~ rs", rs)
    }).finally(() => {
      setLoading(false)
    })
  }, [account, fromAmount]);

  return (
    <div className="container">
      <Card style={{ width: "440px", borderRadius: "16px" }}>
        <Input
          size="large"
          addonBefore="BNB "
          value={fromAmount}
          onChange={handleFromChange}
        />
        <ArrowDownOutlined style={{ margin: "16px 0" }} />
        <Input
          size="large"
          disabled
          addonBefore="BUSD"
          value={toAmount}
          onChange={handleToChange}
        />
        <Button
          size="large"
          type="primary"
          shape="round"
          onClick={handleConfirm}
          loading={loading}
          style={{ width: "100%", marginTop: "20px" }}
        >
          Confirm
        </Button>
      </Card>
    </div>
  );
};
