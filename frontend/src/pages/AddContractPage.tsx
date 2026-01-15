import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import { z } from "zod/v4"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { useChainId } from "wagmi"
import { isAddress } from "viem"

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
import { useContracts, getContractTypes } from "@/hooks/use-contracts"
import type { ContractType } from "@/types/contracts"

const formSchema = z.object({
  name: z.string().min(1, "Name is required").max(50, "Name too long"),
  address: z.string().refine((val) => isAddress(val), {
    message: "Invalid Ethereum address",
  }),
  type: z.enum(["CoverageAgent", "CoverageProvider", "EigenServiceManager"]),
  ownerAddress: z
    .string()
    .optional()
    .refine((val) => !val || isAddress(val), {
      message: "Invalid Ethereum address",
    }),
})

type FormData = {
  name: string
  address: string
  type: "CoverageAgent" | "CoverageProvider" | "EigenServiceManager"
  ownerAddress?: string
}

export function AddContractPage() {
  const navigate = useNavigate()
  const chainId = useChainId()
  const { addContract, contracts } = useContracts()

  const form = useForm<FormData>({
    resolver: zodResolver(formSchema) as unknown as undefined,
    defaultValues: {
      name: "",
      address: "",
      type: "CoverageAgent",
      ownerAddress: "",
    },
  })

  function onSubmit(values: FormData) {
    // Check if contract already exists
    const exists = contracts.some(
      (c) =>
        c.address.toLowerCase() === values.address.toLowerCase() &&
        c.chainId === chainId
    )

    if (exists) {
      toast.error("Contract already exists for this chain")
      return
    }

    addContract({
      name: values.name,
      address: values.address as `0x${string}`,
      type: values.type as ContractType,
      chainId,
      ownerAddress: values.ownerAddress ? values.ownerAddress as `0x${string}` : undefined,
    })

    toast.success("Contract added successfully")
    form.reset()
    navigate("/contracts")
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
              <FormField
                control={form.control}
                name="name"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Name</FormLabel>
                    <FormControl>
                      <Input placeholder="My Coverage Agent" {...field} />
                    </FormControl>
                    <FormDescription>
                      A friendly name to identify this contract
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="address"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Contract Address</FormLabel>
                    <FormControl>
                      <Input placeholder="0x..." {...field} />
                    </FormControl>
                    <FormDescription>
                      The Ethereum address of the contract
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="type"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Contract Type</FormLabel>
                    <Select
                      onValueChange={field.onChange}
                      defaultValue={field.value}
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

              <FormField
                control={form.control}
                name="ownerAddress"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Owner Address (Optional)</FormLabel>
                    <FormControl>
                      <Input placeholder="0x..." {...field} />
                    </FormControl>
                    <FormDescription>
                      The address that owns/controls this contract (for
                      simulation purposes)
                    </FormDescription>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <Button type="submit" className="w-full">
                Add Contract
              </Button>
            </form>
          </Form>
        </CardContent>
      </Card>
    </div>
  )
}
