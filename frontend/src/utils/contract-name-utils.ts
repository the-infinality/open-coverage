import type { ContractType } from "@/types/contracts"

// Dune-themed names for random contract name generation
const duneNames = [
  "muaddib", "atreides", "harkonnen", "fremen", "sardaukar", "mentat", "kwisatz", "shaihulud",
  "paul", "leto", "jessica", "duncan", "gurney", "stilgar", "chani", "irulan",
  "baron", "feyd", "rabban", "vladimir", "glossu", "piter", "thufir", "yueh",
  "arrakis", "caladan", "giedi", "kaitain", "salusa", "ix", "tleilax", "bene"
]

/**
 * Generate a unique random name based on contract type, avoiding collisions with existing contracts
 * @param type - The contract type (CoverageAgent or CoverageProvider)
 * @param existingContracts - Array of existing contracts to avoid name collisions
 * @returns A unique contract name
 */
export function generateContractName(
  type: ContractType,
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

