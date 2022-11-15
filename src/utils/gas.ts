import { Interface } from '@ethersproject/abi'
import BigNumber from 'bignumber.js'
import { parseUnits } from '@ethersproject/units'

import { rpcProvider } from "./provider"

type TxParam = {
    from: string
    to: string
    message: string
    signature: string
    value: string
}

export async function getSwapGas(txParam: TxParam) {
    const gasPrice =  (await rpcProvider.getGasPrice()).toString()
    const iface = new Interface([
        "function swapRequest(bytes calldata message, bytes calldata signature)"
    ])
    const data = iface.encodeFunctionData('swapRequest', [txParam.message, txParam.signature])
    const estimatedGas = (await rpcProvider.estimateGas({
      from: txParam.from,
      to: txParam.to,
      data,
      value: txParam.value,
    })).toString()

    return parseUnits(new BigNumber(gasPrice).times(estimatedGas).toString(), 18).toString()
}