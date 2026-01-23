import { useEffect, useMemo, useState } from "react"
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
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { useContracts } from "@/hooks/use-contracts"
import { getContractTypes } from "@/lib/contract-utils"
import { getSupportedChainsInfo, getPublicClientForChain } from "@/lib/wagmi"
import { cn, generateContractName } from "@/lib/utils"
import type { ContractType, ProviderType } from "@/types/contracts"
import eigenlayerLogo from "@/assets/eigenlayer.jpg"
import catalysisLogo from "@/assets/catalysis.jpg"
import symbioticLogo from "@/assets/symbiotic.png"
import { useInterfaceSupport, useCheckCoverageProvider } from "@/hooks/use-interface-support"
import type { InterfaceName } from "@/lib/interface-ids"

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
    type: z.enum(["CoverageAgent", "CoverageProvider", "EigenOperatorProxy"]),
    providerType: z.enum(["EigenLayer", "Catalysis", "Symbiotic"]).optional(),
})

type FormData = {
    name: string
    address: string
    chainId: number
    type: "CoverageAgent" | "CoverageProvider" | "EigenOperatorProxy"
    providerType?: ProviderType
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

// Mapping from contract type to required interface
const CONTRACT_TYPE_INTERFACES: Record<ContractType, InterfaceName> = {
    CoverageAgent: "ICoverageAgent",
    CoverageProvider: "ICoverageProvider",
    EigenOperatorProxy: "IEigenOperatorProxy",
}

export function AddContractPage() {
    const navigate = useNavigate()
    const connectedChainId = useChainId()
    const { addContract, contracts } = useContracts()
    const supportedChains = getSupportedChainsInfo()

    // Contract existence check state
    const [contractExists, setContractExists] = useState<boolean | null>(null)
    const [isCheckingExists, setIsCheckingExists] = useState(false)

    const form = useForm<FormData>({
        resolver: zodResolver(formSchema) as unknown as undefined,
        defaultValues: {
            name: "",
            address: "",
            chainId: connectedChainId,
            type: "CoverageAgent",
            providerType: undefined,
        },
    })

    const watchedType = useWatch({ control: form.control, name: "type" })
    const watchedChainId = useWatch({ control: form.control, name: "chainId" })
    const watchedAddress = useWatch({ control: form.control, name: "address" })

    // Get the required interface for the selected contract type
    const requiredInterface = CONTRACT_TYPE_INTERFACES[watchedType]
    const isAddressValid = isValidAddressFormat(watchedAddress)

    // Check if contract exists at the address
    useEffect(() => {
        const checkContractExists = async () => {
            if (!isAddressValid || !watchedChainId) {
                setContractExists(null)
                setIsCheckingExists(false)
                return
            }

            const chainPublicClient = getPublicClientForChain(watchedChainId)
            if (!chainPublicClient) {
                setContractExists(null)
                setIsCheckingExists(false)
                return
            }

            setIsCheckingExists(true)
            try {
                const code = await chainPublicClient.getBytecode({
                    address: getAddress(watchedAddress),
                })
                const hasCode = code !== undefined && code !== "0x"
                setContractExists(hasCode)
            } catch {
                setContractExists(null)
            } finally {
                setIsCheckingExists(false)
            }
        }

        const timeoutId = setTimeout(checkContractExists, 500)
        return () => clearTimeout(timeoutId)
    }, [watchedAddress, watchedChainId, isAddressValid])

    // Check if the contract supports the required interface (only if contract exists)
    const { isLoading: isCheckingInterface, supportedInterfaces } = useInterfaceSupport(
        isAddressValid && contractExists ? (watchedAddress as `0x${string}`) : "0x0000000000000000000000000000000000000000",
        watchedChainId,
        [requiredInterface]
    )

    // Combined validation status
    const isValidating = isCheckingExists || (contractExists === true && isCheckingInterface)
    const supportsRequiredInterface = useMemo(
        () => contractExists === true && supportedInterfaces.includes(requiredInterface),
        [contractExists, supportedInterfaces, requiredInterface]
    )

    const { coverageProvider } = useCheckCoverageProvider(
        watchedType === "CoverageProvider" ? (watchedAddress as `0x${string}`) : undefined,
        watchedChainId
    )

    // Reset provider type when contract type changes
    useEffect(() => {
        if (watchedType !== "CoverageProvider") {
            form.setValue("providerType", undefined)
        }
    }, [watchedType, form])

    // Auto-generate name when contract type changes
    useEffect(() => {
        form.setValue("name", generateContractName(watchedType, contracts))
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
        const nameExists = contracts.some((c) => c.name.toLowerCase() === values.name.toLowerCase())

        if (nameExists) {
            toast.error("A contract with this name already exists. Please choose a different name.")
            return
        }

        switch (values.type) {
            case "CoverageProvider":
                addContract({
                    name: values.name,
                    address: values.address as `0x${string}`,
                    type: values.type as ContractType,
                    chainId: values.chainId,
                })
                break
            default: {
                addContract({
                    name: values.name,
                    address: values.address as `0x${string}`,
                    type: values.type as ContractType,
                    chainId: values.chainId,
                })
            }
        }

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
                        Add a new contract to interact with. Contracts are stored locally in your
                        browser.
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
                                        <Select onValueChange={field.onChange} value={field.value}>
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
                                            The type of contract determines which ABI and methods
                                            are available
                                        </FormDescription>
                                        <FormMessage />
                                    </FormItem>
                                )}
                            />

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
                                ${
                                    isSelected
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
                                                            <span className="font-medium">
                                                                {chain.name}
                                                            </span>
                                                            {chain.isTestnet && (
                                                                <span
                                                                    className={`text-xs px-1.5 py-0.5 rounded-full ${chain.colors.bg} ${chain.colors.text}`}
                                                                >
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
                                                <Input
                                                    placeholder="0x..."
                                                    {...field}
                                                    className="pr-10"
                                                />
                                                <div className="absolute right-3 top-1/2 -translate-y-1/2">
                                                    {isAddressValid && isValidating && (
                                                        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                                                    )}
                                                    {isAddressValid &&
                                                        !isValidating &&
                                                        supportsRequiredInterface && (
                                                            <CheckCircle2 className="h-4 w-4 text-green-500" />
                                                        )}
                                                    {isAddressValid &&
                                                        !isValidating &&
                                                        (contractExists === false ||
                                                            !supportsRequiredInterface) && (
                                                            <AlertCircle className="h-4 w-4 text-destructive" />
                                                        )}
                                                </div>
                                            </div>
                                        </FormControl>
                                        <FormDescription>
                                            {isAddressValid &&
                                            !isValidating &&
                                            contractExists === false ? (
                                                <span className="text-destructive">
                                                    Contract does not exist
                                                </span>
                                            ) : isAddressValid &&
                                              !isValidating &&
                                              contractExists === true &&
                                              !supportsRequiredInterface ? (
                                                <span className="text-destructive">
                                                    Contract not verified: does not support{" "}
                                                    {requiredInterface}
                                                </span>
                                            ) : isAddressValid &&
                                              !isValidating &&
                                              supportsRequiredInterface ? (
                                                <span className="text-green-600 dark:text-green-400">
                                                    Contract verified
                                                </span>
                                            ) : (
                                                "The Ethereum address of the contract"
                                            )}
                                        </FormDescription>
                                        <FormMessage />
                                    </FormItem>
                                )}
                            />

                            {/* Provider Type Badges - Only shown for CoverageProvider */}
                            {watchedType === "CoverageProvider" && (
                                <div>
                                    <div className="flex flex-wrap gap-3">
                                        {providerTypes.map((provider) => {
                                            const isSelected = coverageProvider === provider.value

                                            const badge = (
                                                <div
                                                    key={provider.value}
                                                    className={cn(
                                                        "relative flex items-center gap-2 px-4 py-2.5 rounded-lg border-2 transition-all",
                                                        {
                                                            "border-primary bg-primary/10 shadow-sm":
                                                                isSelected,
                                                        }
                                                    )}
                                                >
                                                    <img
                                                        src={provider.icon}
                                                        alt={provider.label}
                                                        className={`h-6 w-6 rounded`}
                                                    />
                                                    <span className={`font-medium`}>
                                                        {provider.label}
                                                    </span>
                                                    {isSelected && (
                                                        <CheckCircle2 className="h-4 w-4 text-primary ml-1" />
                                                    )}
                                                </div>
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
                                    <label className="text-sm text-muted-foreground">
                                        The type of coverage provider this contract integrates with
                                    </label>
                                </div>
                            )}

                            {/* Name */}
                            <FormField
                                control={form.control}
                                name="name"
                                render={({ field }) => (
                                    <FormItem>
                                        <FormLabel>Name</FormLabel>
                                        <FormControl>
                                            <Input {...field} />
                                        </FormControl>
                                        <FormDescription>
                                            A friendly name to identify this contract
                                            (auto-generated, feel free to change)
                                        </FormDescription>
                                        <FormMessage />
                                    </FormItem>
                                )}
                            />

                            <Button
                                type="submit"
                                className="w-full"
                                disabled={
                                    !isAddressValid || isValidating || !supportsRequiredInterface
                                }
                                size="lg"
                            >
                                {isValidating ? (
                                    <>
                                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                                        Checking contract...
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
