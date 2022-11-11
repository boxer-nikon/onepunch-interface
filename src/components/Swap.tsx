import { ChangeEvent, useState, useEffect, useCallback } from "react";
import { useWeb3React } from "@web3-react/core";
import type { Web3Provider } from "@ethersproject/providers";
import { Contract } from "@ethersproject/contracts";
import { MaxInt256 } from "@ethersproject/constants";
import { Card, Input, Button } from "antd";
import { ArrowDownOutlined } from "@ant-design/icons";

import { quote, Side, IQuote } from "../apis";
import ERC20ABI from "../abis/ERC20.json";
import DexLiquidityProviderABI from "../abis/DexLiquidityProvider.json";
import QuickLiquidityProviderABI from "../abis/QuickLiquidityProvider.json";

const USDT = "";
const dexLiquidityProviderAddress =
  "0xF17E9322eb6dA7DD39a2FED1B72abC921154759d";
const quickLiquidityProviderAddress =
  "0xc817790EAa4e1F058908Eaf90e2a2E92FBb091B4";

export const Swap = () => {
  const [isBase, setIsBase] = useState(true);
  const [loading, setLoading] = useState(false);
  const [quoteModel, setQuoteModel] = useState<IQuote>({} as IQuote);
  const [fromAmount, setFromAmount] = useState("0");
  const [toAmount, setToAmount] = useState("0");
  const { account, library } = useWeb3React<Web3Provider>();

  const handleFromChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setIsBase(true);
    setFromAmount(e.currentTarget.value);
  }, []);

  const handleToChange = useCallback((e: ChangeEvent<HTMLInputElement>) => {
    setIsBase(false);
    setToAmount(e.currentTarget.value);
  }, []);

  const handleConfirm = useCallback(async () => {
    if (!account) return;

    const targetContract =
      quoteModel.settlementMode === "0"
        ? new Contract(
            quickLiquidityProviderAddress,
            QuickLiquidityProviderABI,
            library?.getSigner()
          )
        : new Contract(
            dexLiquidityProviderAddress,
            DexLiquidityProviderABI,
            library?.getSigner()
          );
    if (!isBase) {
      // ensure allowonce elliagle
      const fromToken = new Contract(USDT, ERC20ABI);
      const allowonce = await fromToken.allowance(
        account,
        targetContract.address
      );
      if (!allowonce.gt(fromAmount)) {
        const tx = await fromToken.approve(targetContract.address, MaxInt256);
        await tx.wait();
      }
    }
    await targetContract.swapRequest(quoteModel.message, quoteModel.sign);
  }, [account, fromAmount, library, isBase, quoteModel]);

  useEffect(() => {
    async function rfq() {
      setLoading(true);
      const param = isBase
        ? {
            baseCurrency: "BNB",
            baseCurrencySize: fromAmount,
            quoteCurrency: "USDT",
            quoteCurrencySize: "",
            side: Side.BUY,
            userOnChainAddress: account || "",
          }
        : {
            baseCurrency: "BNB",
            baseCurrencySize: "",
            quoteCurrency: "USDT",
            quoteCurrencySize: toAmount,
            side: Side.SELL,
            userOnChainAddress: account || "",
          };
      try {
        const quoteRes = await quote(param);
        setQuoteModel(quoteRes);
      } catch (e) {
      } finally {
        setLoading(false);
      }
    }

    rfq();
  }, [isBase, fromAmount, toAmount, account]);

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
          addonBefore="USDT"
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
