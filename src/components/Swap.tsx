import { ChangeEvent, useState, useEffect, useCallback } from "react";
import { useWeb3React } from "@web3-react/core";
import type { Web3Provider } from "@ethersproject/providers";
import { Card, Input, Button } from "antd";
import { ArrowDownOutlined } from "@ant-design/icons";

import { getQuotePrice } from "../apis";

export const Swap = () => {
  const [loading, setLoading] = useState(false)
  const [fromAmount, setFromAmount] = useState("0");
  const [toAmount, setToAmount] = useState("0");
  const { account } = useWeb3React<Web3Provider>();

  const handleFromChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setFromAmount(e.currentTarget.value);
  }, []);

  const handleToChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setToAmount(e.currentTarget.value);
  }, []);

  const handleConfirm = useCallback(() => {
    // 1. get latest quote
    // 2. call swap contract
  }, []);

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
