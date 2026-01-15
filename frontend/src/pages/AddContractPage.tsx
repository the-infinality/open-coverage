import { useEffect, useState } from "react"
import { useForm, useWatch } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod/v4"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { useChainId } from "wagmi"
import { getAddress } from "viem"
import { Loader2, CheckCircle2, AlertCircle } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"
import { useContracts } from "@/hooks/use-contracts"
import { getContractTypes } from "@/lib/contract-utils"
import { getSupportedChainsInfo, getPublicClientForChain } from "@/lib/wagmi"
import { coverageAgentAbi, coverageProviderAbi } from "@/generated/abis"
import type { ContractType, ProviderType } from "@/types/contracts"
import eigenlayerLogo from "@/assets/eigenlayer.jpg"
import catalysisLogo from "@/assets/catalysis.jpg"
import symbioticLogo from "@/assets/symbiotic.png"

// Get supported chain IDs for validation
const supportedChainIds = getSupportedChainsInfo().map((c) => c.id)

// Validate address format without checksum - just check length and hex format
const isValidAddressFormat = (address: string): boolean => {
  return /^0x[a-fA-F0-9]{40}$/.test(address)
}

const formSchema = z.object({
  name: z.string().min(1, "Name is required").max(50, "Name too long"),
  address: z.string().refine((val) => isValidAddressFormat(val), {
    message: "Invalid Ethereum address format",
  }),
  chainId: z.number().refine((val) => supportedChainIds.includes(val), {
    message: "Please select a valid chain",
  }),
  type: z.enum(["CoverageAgent", "CoverageProvider"]),
  providerType: z.enum(["EigenLayer", "Catalysis", "Symbiotic"]).optional(),
})

type FormData = {
  name: string
  address: string
  chainId: number
  type: "CoverageAgent" | "CoverageProvider"
  providerType?: ProviderType
}

// Dune-themed names for random contract name generation
const duneNames = [
  "muaddib", "atreides", "harkonnen", "fremen", "sardaukar", "mentat", "kwisatz", "shaihulud",
  "paul", "leto", "jessica", "duncan", "gurney", "stilgar", "chani", "irulan",
  "baron", "feyd", "rabban", "vladimir", "glossu", "piter", "thufir", "yueh",
  "arrakis", "caladan", "giedi", "kaitain", "salusa", "ix", "tleilax", "bene"
]

// Generate a unique random name based on contract type, avoiding collisions with existing contracts
function generateRandomName(
  type: "CoverageAgent" | "CoverageProvider",
  existingContracts: Array<{ name: string }>
): string {
  const prefix = type
  const existingNames = new Set(existingContracts.map((c) => c.name.toLowerCase()))
  
  // Try up to 100 times to find a unique name
  for (let attempt = 0; attempt < 100; attempt++) {
    const duneName = duneNames[Math.floor(Math.random() * duneNames.length)]
    const baseName = `${prefix}-${duneName}`
    
    // If base name is unique, return it
    if (!existingNames.has(baseName.toLowerCase())) {
      return baseName
    }
    
    // If base name exists, try with a number suffix
    for (let num = 1; num <= 999; num++) {
      const numberedName = `${baseName}-${num}`
      if (!existingNames.has(numberedName.toLowerCase())) {
        return numberedName
      }
    }
  }
  
  // Fallback: use timestamp if all else fails
  return `${prefix}-${Date.now()}`
}

// Provider type options with metadata
const providerTypes: {
  value: ProviderType
  label: string
  icon: string
  disabled: boolean
  comingSoon?: boolean
}[] = [
  {
    value: "EigenLayer",
    label: "EigenLayer",
    icon: eigenlayerLogo,
    disabled: false,
  },
  {
    value: "Catalysis",
    label: "Catalysis",
    icon: catalysisLogo,
    disabled: true,
    comingSoon: true,
  },
  {
    value: "Symbiotic",
    label: "Symbiotic",
    icon: symbioticLogo,
    disabled: true,
    comingSoon: true,
  },
]

interface ContractValidationState {
  isValidating: boolean
  hasCode: boolean | null
  ownerAddress: string | null
  error: string | null
}

export function AddContractPage() {
  const navigate = useNavigate()
  const connectedChainId = useChainId()
  const { addContract, contracts } = useContracts()
  const supportedChains = getSupportedChainsInfo()

  const [validation, setValidation] = useState<ContractValidationState>({
    isValidating: false,
    hasCode: null,
    ownerAddress: null,
    error: null,
  })

  const form = useForm<FormData>({
    resolver: zodResolver(formSchema) as unknown as undefined,
    defaultValues: {
      name: generateRandomName("CoverageAgent", contracts),
      address: "",
      chainId: connectedChainId,
      type: "CoverageAgent",
      providerType: undefined,
    },
  })

  const watchedType = useWatch({ control: form.control, name: "type" })
  const watchedChainId = useWatch({ control: form.control, name: "chainId" })
  const watchedAddress = useWatch({ control: form.control, name: "address" })

  // Validate contract address when it changes
  useEffect(() => {
    const validateContract = async () => {
      if (!watchedAddress || !isValidAddressFormat(watchedAddress)) {
        setValidation({ isValidating: false, hasCode: null, ownerAddress: null, error: null })
        return
      }

      if (!watchedChainId) {
        setValidation({ isValidating: false, hasCode: null, ownerAddress: null, error: "Please select a chain" })
        return
      }

      // Get public client for the selected chain
      const chainPublicClient = getPublicClientForChain(watchedChainId)
      if (!chainPublicClient) {
        setValidation({ isValidating: false, hasCode: null, ownerAddress: null, error: "Invalid chain" })
        return
      }

      setValidation({ isValidating: true, hasCode: null, ownerAddress: null, error: null })

      try {
        // Check if there's code at the address
        const code = await chainPublicClient.getBytecode({ address: getAddress(watchedAddress) })
        const hasCode = code !== undefined && code !== "0x"

        if (!hasCode) {
          setValidation({
            isValidating: false,
            hasCode: false,
            ownerAddress: null,
            error: "No contract found at this address",
          })
          return
        }

        // Try to get the owner/coordinator based on contract type
        let ownerAddress: string | null = null
        
        try {
          if (watchedType === "CoverageAgent") {
            // Use coordinator method for CoverageAgent
            const result = await chainPublicClient.readContract({
              address: getAddress(watchedAddress),
              abi: coverageAgentAbi,
              functionName: "coordinator",
            })
            ownerAddress = result as string
          } else if (watchedType === "CoverageProvider") {
            // Use owner method for CoverageProvider
            const result = await chainPublicClient.readContract({
              address: getAddress(watchedAddress),
              abi: coverageProviderAbi,
              functionName: "owner",
            })
            ownerAddress = result as string
          }
        } catch {
          // Owner detection failed, but contract exists
        }

        setValidation({
          isValidating: false,
          hasCode: true,
          ownerAddress,
          error: null,
        })
      } catch {
        setValidation({
          isValidating: false,
          hasCode: null,
          ownerAddress: null,
          error: "Failed to validate contract",
        })
      }
    }

    const timeoutId = setTimeout(validateContract, 500)
    return () => clearTimeout(timeoutId)
  }, [watchedAddress, watchedChainId, watchedType])

  // Reset provider type when contract type changes
  useEffect(() => {
    if (watchedType !== "CoverageProvider") {
      form.setValue("providerType", undefined)
    }
  }, [watchedType, form])

  // Auto-generate name when contract type changes
  useEffect(() => {
    const currentName = form.getValues("name")
    // Generate name if empty or matches the auto-generated pattern
    const autoGeneratedPattern = /^(Agent|Provider)-\w+(-\d+)?$/
    if (!currentName || autoGeneratedPattern.test(currentName)) {
      form.setValue("name", generateRandomName(watchedType, contracts))
    }
  }, [watchedType, form, contracts])

  function onSubmit(values: FormData) {
    // Check if contract already exists
    const exists = contracts.some(
      (c) =>
        c.address.toLowerCase() === values.address.toLowerCase() &&
        c.chainId === values.chainId
    )

    if (exists) {
      toast.error("Contract already exists for this chain")
      return
    }

    // Check if name already exists
    const nameExists = contracts.some(
      (c) => c.name.toLowerCase() === values.name.toLowerCase()
    )

    if (nameExists) {
      toast.error("A contract with this name already exists. Please choose a different name.")
      return
    }

    // Require provider type for CoverageProvider
    if (values.type === "CoverageProvider" && !values.providerType) {
      toast.error("Please select a provider type")
      return
    }

    addContract({
      name: values.name,
      address: values.address as `0x${string}`,
      type: values.type as ContractType,
      chainId: values.chainId,
      ownerAddress: validation.ownerAddress ? validation.ownerAddress as `0x${string}` : undefined,
      providerType: values.providerType,
    })

    toast.success("Contract added successfully")
    form.reset()
    navigate("/")
  }

  return (
    <div className="mx-auto max-w-2xl">
      <Card>
        <CardHeader>
          <CardTitle>Add Contract</CardTitle>
          <CardDescription>
            Add a new contract to interact with. Contracts are stored locally in
            your browser.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
              {/* Contract Type - First */}
              <FormField
                control={form.control}
                name="type"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Contract Type</FormLabel>
                    <Select
                      onValueChange={field.onChange}
                      value={field.value}
                    >
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Select contract type" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {getContractTypes().map((type) => (
                          <SelectItem key={type.value} value={type.value}>
                            {type.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormDescription>
                      The type of contract determines which ABI and methods are
                      available
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Provider Type Badges - Only shown for CoverageProvider */}
              {watchedType === "CoverageProvider" && (
                <FormField
                  control={form.control}
                  name="providerType"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Provider Type</FormLabel>
                      <FormControl>
                        <div className="flex flex-wrap gap-3">
                          {providerTypes.map((provider) => {
                            const isSelected = field.value === provider.value
                            const isDisabled = provider.disabled

                            const badge = (
                              <button
                                key={provider.value}
                                type="button"
                                disabled={isDisabled}
                                onClick={() => {
                                  if (!isDisabled) {
                                    field.onChange(provider.value)
                                  }
                                }}
                                className={`
                                  relative flex items-center gap-2 px-4 py-2.5 rounded-lg border-2 transition-all
                                  ${isSelected
                                    ? "border-primary bg-primary/10 shadow-sm"
                                    : isDisabled
                                      ? "border-muted bg-muted/30 opacity-50 cursor-not-allowed"
                                      : "border-border hover:border-primary/50 hover:bg-accent cursor-pointer"
                                  }
                                `}
                              >
                                <img
                                  src={provider.icon}
                                  alt={provider.label}
                                  className={`h-6 w-6 rounded ${isDisabled ? "grayscale" : ""}`}
                                />
                                <span className={`font-medium ${isDisabled ? "text-muted-foreground" : ""}`}>
                                  {provider.label}
                                </span>
                                {isSelected && (
                                  <CheckCircle2 className="h-4 w-4 text-primary ml-1" />
                                )}
                              </button>
                            )

                            if (provider.comingSoon) {
                              return (
                                <Tooltip key={provider.value}>
                                  <TooltipTrigger asChild>
                                    {badge}
                                  </TooltipTrigger>
                                  <TooltipContent>
                                    <p>Coming Soon</p>
                                  </TooltipContent>
                                </Tooltip>
                              )
                            }

                            return badge
                          })}
                        </div>
                      </FormControl>
                      <FormDescription>
                        Select the restaking protocol this provider integrates with
                      </FormDescription>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {/* Chain - Second */}
              <FormField
                control={form.control}
                name="chainId"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Chain</FormLabel>
                    <FormControl>
                      <div className="flex flex-wrap gap-3">
                        {supportedChains.map((chain) => {
                          const isSelected = field.value === chain.id

                          return (
                            <button
                              key={chain.id}
                              type="button"
                              onClick={() => field.onChange(chain.id)}
                              className={`
                                relative flex items-center gap-2 px-4 py-2.5 rounded-lg border-2 transition-all
                                ${isSelected
                                  ? "border-primary bg-primary/10 shadow-sm"
                                  : "border-border hover:border-primary/50 hover:bg-accent cursor-pointer"
                                }
                              `}
                            >
                              <img
                                src={chain.icon}
                                alt={chain.name}
                                className="h-6 w-6 rounded-full"
                              />
                              <span className="font-medium">{chain.name}</span>
                              {chain.isTestnet && (
                                <span className={`text-xs px-1.5 py-0.5 rounded-full ${chain.colors.bg} ${chain.colors.text}`}>
                                  Testnet
                                </span>
                              )}
                              {isSelected && (
                                <CheckCircle2 className="h-4 w-4 text-primary ml-1" />
                              )}
                            </button>
                          )
                        })}
                      </div>
                    </FormControl>
                    <FormDescription>
                      The blockchain network where this contract is deployed
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Contract Address - Third */}
              <FormField
                control={form.control}
                name="address"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Contract Address</FormLabel>
                    <FormControl>
                      <div className="relative">
                        <Input placeholder="0x..." {...field} className="pr-10" />
                        <div className="absolute right-3 top-1/2 -translate-y-1/2">
                          {validation.isValidating && (
                            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                          )}
                          {!validation.isValidating && validation.hasCode === true && (
                            <CheckCircle2 className="h-4 w-4 text-green-500" />
                          )}
                          {!validation.isValidating && validation.hasCode === false && (
                            <AlertCircle className="h-4 w-4 text-destructive" />
                          )}
                        </div>
                      </div>
                    </FormControl>
                    <FormDescription>
                      {validation.error ? (
                        <span className="text-destructive">{validation.error}</span>
                      ) : validation.hasCode && validation.ownerAddress ? (
                        <span className="text-green-600 dark:text-green-400">
                          Contract found • Owner detected
                        </span>
                      ) : validation.hasCode ? (
                        <span className="text-green-600 dark:text-green-400">
                          Contract found
                        </span>
                      ) : (
                        "The Ethereum address of the contract"
                      )}
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Name */}
              <FormField
                control={form.control}
                name="name"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Name</FormLabel>
                    <FormControl>
                      <Input placeholder="Agent-muaddib" {...field} />
                    </FormControl>
                    <FormDescription>
                      A friendly name to identify this contract (auto-generated, feel free to change)
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <Button 
                type="submit" 
                className="w-full"
                disabled={!validation.hasCode || validation.isValidating}
              >
                {validation.isValidating ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Verifying Contract...
                  </>
                ) : (
                  "Add Contract"
                )}
              </Button>
            </form>
          </Form>
        </CardContent>
      </Card>
    </div>
  )
}
