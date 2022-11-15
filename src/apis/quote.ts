import axios from "axios";

export enum Side {
  BUY = "BUY",
  SELL = "SELL",
}

type QuoteParams = {
  baseCurrency: string;
  baseCurrencySize?: string;
  quoteCurrency: string;
  quoteCurrencySize?: string;
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

const API_HOST = "http://localhost:8080/proxy";

type IResponse = {
  status: "ERROR" | "OK";
  data: IQuote;
};

export const quote = async (params: QuoteParams): Promise<IQuote | null> => {
  const res = await axios.post<IResponse>(`${API_HOST}/api/v1/dex/quote`, {
    body: params,
  });
  if (res.data.status === "OK") {
    return res.data.data;
  }

  return null;
};

export const getPairs = async () => {
  return fetch(`${API_HOST}/api/v1/dex/pairs`, {
    method: "POST",
  });
};
