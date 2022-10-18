import { useWeb3React } from "@web3-react/core";
import { InjectedConnector } from "@web3-react/injected-connector";
import { useCallback } from "react";

const injected = new InjectedConnector({ supportedChainIds: [97] });

export const Header = () => {
  const { activate, active, deactivate } = useWeb3React();

  const handleConnect = useCallback(() => {
    if (active) {
      return deactivate()
    }
    activate(injected, (error) => {
      console.log("🚀 ~ file: Header.tsx ~ line 12 ~ activate ~ error", error);
    });
  }, [active, activate, deactivate]);

  return (
    <header className="App-header">
      <span className="header-connect" onClick={handleConnect}>{ active ? 'DisConnect' : 'Connect'}</span>
    </header>
  );
};
