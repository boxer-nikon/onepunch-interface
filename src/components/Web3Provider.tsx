import React from 'react'
import { Web3ReactProvider } from '@web3-react/core'
import { Web3Provider as EtherWeb3Provider, ExternalProvider } from '@ethersproject/providers'


function getLibrary(provider: ExternalProvider) {
  return new EtherWeb3Provider(provider)
}

export const Web3Provider: React.FC<{ children: React.ReactNode}> = ({ children }) => (
  <Web3ReactProvider getLibrary={getLibrary}>{children}</Web3ReactProvider>
)
