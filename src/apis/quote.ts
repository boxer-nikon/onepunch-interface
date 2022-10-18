export const getQuotePrice = async () => {
  return fetch("https://www.binance.com/bapi/asset/v1/public/asset/asset/get-asset-logo", {
    method: "GET",
  });
};
