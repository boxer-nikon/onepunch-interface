export enum Side {
  BUY = "BUY",
  SELL = "SELL",
}

type QuoteParams = {
  baseCurrency: string;
  baseCurrencySize: string;
  quoteCurrency: string;
  quoteCurrencySize: string;
  side: Side;
  userOnChainAddress?: string;
};
export type IQuote = {
  baseCurrency: string;
  baseCurrencySize: string;
  compensationAmount: string;
  compensationCurrency: string;
  expiredTime: number;
  message: string;
  price: string;
  quoteCurrency: string;
  quoteCurrencySize: string;
  quoteId: string;
  settlementMode: string;
  side: Side;
  sign: string;
};
export const quote = async (params: QuoteParams): Promise<IQuote> => {
  const res = await fetch("http://10.100.174.55:10357/api/v1/dex/quote", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });

  return res.json()
};

export const getPairs = async () => {
  return fetch("http://10.100.174.55:10357/api/v1/dex/pairs", {
    method: "POST",
  });
};
