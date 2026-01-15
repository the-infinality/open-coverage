import { useState, useEffect } from "react"
import { useParams, Link } from "react-router-dom"
import { useChainId, usePublicClient, useBlockNumber } from "wagmi"
import { type Abi, type AbiEvent, decodeEventLog } from "viem"
import { toast } from "sonner"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { ScrollArea } from "@/components/ui/scroll-area"
import { useContracts } from "@/hooks/use-contracts"
import { getAbiForContractType } from "@/generated/abis"
import { truncateAddress } from "@/lib/utils"
import { RefreshCw } from "lucide-react"

interface ContractLog {
  address: `0x${string}`
  blockNumber: bigint
  transactionHash: `0x${string}`
  logIndex: number
  eventName: string
  args: Record<string, unknown>
}

export function LogsPage() {
  const { contractId } = useParams<{ contractId?: string }>()
  const { contracts, getContractById } = useContracts()
  const chainId = useChainId()
  const publicClient = usePublicClient()
  const { data: currentBlock } = useBlockNumber()

  const [selectedContractId, setSelectedContractId] = useState<string | null>(
    contractId || null
  )
  const [logs, setLogs] = useState<ContractLog[]>([])
  const [isLoading, setIsLoading] = useState(false)
  const [fromBlock, setFromBlock] = useState<string>("")
  const [toBlock, setToBlock] = useState<string>("")

  const selectedContract = selectedContractId
    ? getContractById(selectedContractId)
    : null

  const abi = selectedContract
    ? (getAbiForContractType(selectedContract.type) as Abi)
    : []

  const events = abi.filter(
    (item): item is AbiEvent => item.type === "event"
  )

  // Filter contracts by current chain
  const chainContracts = contracts.filter((c) => c.chainId === chainId)

  const fetchLogs = async () => {
    if (!selectedContract || !publicClient) return

    setIsLoading(true)
    try {
      const from = fromBlock ? BigInt(fromBlock) : (currentBlock || 0n) - 1000n
      const to = toBlock ? BigInt(toBlock) : currentBlock || "latest"

      const rawLogs = await publicClient.getLogs({
        address: selectedContract.address,
        fromBlock: from,
        toBlock: to,
      })

      const decodedLogs: ContractLog[] = []

      for (const log of rawLogs) {
        try {
          const decoded = decodeEventLog({
            abi,
            data: log.data,
            topics: log.topics,
          })

          const argsObj: Record<string, unknown> = {}
          if (decoded.args && typeof decoded.args === 'object') {
            if (Array.isArray(decoded.args)) {
              decoded.args.forEach((arg, i) => {
                argsObj[`arg${i}`] = arg
              })
            } else {
              Object.assign(argsObj, decoded.args)
            }
          }

          decodedLogs.push({
            address: log.address,
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash,
            logIndex: log.logIndex,
            eventName: decoded.eventName || "Unknown",
            args: argsObj,
          })
        } catch {
          // Skip logs that don't match our ABI
        }
      }

      setLogs(decodedLogs)
      toast.success(`Found ${decodedLogs.length} logs`)
    } catch (error) {
      console.error("Error fetching logs:", error)
      toast.error("Failed to fetch logs")
    } finally {
      setIsLoading(false)
    }
  }

  useEffect(() => {
    if (selectedContract && currentBlock) {
      setFromBlock((currentBlock - 1000n).toString())
      setToBlock(currentBlock.toString())
    }
  }, [selectedContract, currentBlock])

  if (chainContracts.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <h2 className="text-lg font-medium">No contracts on this chain</h2>
        <p className="mb-4 text-center text-sm text-muted-foreground">
          Add a contract for this chain to view logs.
        </p>
        <Button asChild>
          <Link to="/">Add Contract</Link>
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold">Contract Logs</h2>
        <p className="text-muted-foreground">View event logs for your contracts</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Select Contract</CardTitle>
          <CardDescription>Choose a contract to view logs</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Select
            value={selectedContractId || ""}
            onValueChange={(value) => setSelectedContractId(value)}
          >
            <SelectTrigger>
              <SelectValue placeholder="Select a contract" />
            </SelectTrigger>
            <SelectContent>
              {chainContracts.map((contract) => (
                <SelectItem key={contract.id} value={contract.id}>
                  {contract.name} ({truncateAddress(contract.address)})
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          {selectedContract && (
            <>
              <div className="grid gap-4 md:grid-cols-2">
                <div>
                  <Label>From Block</Label>
                  <Input
                    type="number"
                    value={fromBlock}
                    onChange={(e) => setFromBlock(e.target.value)}
                    placeholder="From block number"
                  />
                </div>
                <div>
                  <Label>To Block</Label>
                  <Input
                    type="number"
                    value={toBlock}
                    onChange={(e) => setToBlock(e.target.value)}
                    placeholder="To block number"
                  />
                </div>
              </div>

              <Button onClick={fetchLogs} disabled={isLoading}>
                <RefreshCw
                  className={`mr-2 size-4 ${isLoading ? "animate-spin" : ""}`}
                />
                Fetch Logs
              </Button>
            </>
          )}
        </CardContent>
      </Card>

      {selectedContract && events.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Available Events</CardTitle>
            <CardDescription>
              Events that can be emitted by this contract
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-2">
              {events.map((event, index) => (
                <span
                  key={index}
                  className="rounded-full bg-muted px-3 py-1 text-sm font-medium"
                >
                  {event.name}
                </span>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {logs.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Event Logs ({logs.length})</CardTitle>
            <CardDescription>
              Showing logs from block {fromBlock} to {toBlock}
            </CardDescription>
          </CardHeader>
          <CardContent>
            <ScrollArea className="h-[500px]">
              <div className="space-y-4">
                {logs.map((log, index) => (
                  <div
                    key={index}
                    className="rounded-lg border p-4 hover:bg-muted/50"
                  >
                    <div className="mb-2 flex items-center justify-between">
                      <span className="rounded-full bg-primary/10 px-3 py-1 text-sm font-medium text-primary">
                        {log.eventName}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        Block {log.blockNumber.toString()}
                      </span>
                    </div>
                    <div className="mb-2 text-xs text-muted-foreground">
                      Tx: {truncateAddress(log.transactionHash, 10)}
                    </div>
                    {Object.keys(log.args).length > 0 && (
                      <div className="mt-2 rounded bg-muted p-3">
                        <pre className="text-xs overflow-x-auto">
                          {JSON.stringify(
                            log.args,
                            (_, v) => (typeof v === "bigint" ? v.toString() : v),
                            2
                          )}
                        </pre>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </ScrollArea>
          </CardContent>
        </Card>
      )}

      {logs.length === 0 && selectedContract && !isLoading && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-12">
            <p className="text-center text-sm text-muted-foreground">
              No logs found. Try adjusting the block range or fetch logs.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
