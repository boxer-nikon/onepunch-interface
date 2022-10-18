import React from 'react';

import { Swap } from './components/Swap';
import { Header } from './components/Header'
import { Web3Provider } from './components/Web3Provider'

import './App.css';
import 'antd/dist/antd.css'

function App() {
  return (
    <div className="App">
      <Web3Provider>
        <Header />
        <Swap />
      </Web3Provider>
    </div>
  );
}

export default App;
