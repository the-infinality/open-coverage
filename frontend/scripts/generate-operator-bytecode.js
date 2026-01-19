#!/usr/bin/env node
/**
 * Script to generate eigen-operator-proxy-deployment.ts from Foundry compiled artifacts
 * 
 * Usage: node scripts/generate-operator-bytecode.js
 */

import { readFileSync, writeFileSync, existsSync } from 'fs'
import { dirname, join, resolve } from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Path to the Foundry output artifact
const ARTIFACT_PATH = resolve(__dirname, '../../out/EigenOperatorProxy.sol/EigenOperatorProxy.json')

// Output path for the generated TypeScript file
const OUTPUT_PATH = resolve(__dirname, '../src/generated/eigen-operator-proxy-deployment.ts')

function main() {
  console.log('🔧 Generating EigenOperatorProxy deployment code...')
  
  // Check if artifact exists
  if (!existsSync(ARTIFACT_PATH)) {
    console.error(`❌ Artifact not found at: ${ARTIFACT_PATH}`)
    console.error('   Make sure to run `forge build` first.')
    process.exit(1)
  }

  // Read and parse the artifact
  const artifactContent = readFileSync(ARTIFACT_PATH, 'utf-8')
  const artifact = JSON.parse(artifactContent)

  // Extract the bytecode
  const bytecode = artifact.bytecode?.object
  if (!bytecode) {
    console.error('❌ Bytecode not found in artifact')
    process.exit(1)
  }

  // Extract constructor ABI (filter for constructor type)
  const constructorAbi = artifact.abi?.filter(item => item.type === 'constructor')
  if (!constructorAbi || constructorAbi.length === 0) {
    console.error('❌ Constructor ABI not found in artifact')
    process.exit(1)
  }

  // Generate the TypeScript file content
  const tsContent = `/**
 * EigenOperatorProxy deployment ABI and bytecode
 * 
 * AUTO-GENERATED FILE - DO NOT EDIT DIRECTLY
 * Generated from Foundry compiled artifact at:
 * out/EigenOperatorProxy.sol/EigenOperatorProxy.json
 * 
 * Run \`yarn generate-operator-bytecode\` to regenerate this file.
 */

// Constructor ABI for deploying EigenOperatorProxy
export const eigenOperatorProxyDeployAbi = ${JSON.stringify(constructorAbi, null, 2)} as const

// Bytecode for EigenOperatorProxy contract
export const eigenOperatorProxyBytecode = '${bytecode}' as \`0x\${string}\`
`

  // Write the output file
  writeFileSync(OUTPUT_PATH, tsContent)
  
  console.log(`✅ Generated: ${OUTPUT_PATH}`)
  console.log(`   Bytecode length: ${bytecode.length} characters`)
  console.log(`   Constructor ABI items: ${constructorAbi.length}`)
}

main()

