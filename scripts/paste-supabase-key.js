/**
 * Lê uma chave do Supabase da área de transferência, valida e grava em
 * .env.local — sem que ela precise passar por editor, chat ou terminal.
 *
 *   1. copie a chave no painel do Supabase (botão de copiar)
 *   2. node scripts/paste-supabase-key.js anon
 *      node scripts/paste-supabase-key.js service
 *
 * Valida antes de gravar: integridade (sem caractere mascarado), formato,
 * papel declarado no JWT e projeto de origem.
 */

const fs = require('fs')
const path = require('path')
const { execSync } = require('child_process')

const OK = '\x1b[32m✓\x1b[0m'
const NO = '\x1b[31m✗\x1b[0m'

const PROJECT_REF = 'lwlpjeevrxzjtcmcrhaq'
const ENV_FILE = path.join(__dirname, '..', '.env.local')

const ALVOS = {
  anon: { varName: 'NEXT_PUBLIC_SUPABASE_ANON_KEY', role: 'anon', rotulo: 'anon / publishable' },
  service: { varName: 'SUPABASE_SERVICE_ROLE_KEY', role: 'service_role', rotulo: 'service_role / secret' },
}

function morrer(msg, dica) {
  console.log(`\n${NO} ${msg}`)
  if (dica) console.log(`    ${dica}`)
  console.log()
  process.exit(1)
}

function decodificarJwt(token) {
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    return JSON.parse(Buffer.from(payload, 'base64').toString('utf8'))
  } catch {
    return null
  }
}

const alvo = ALVOS[process.argv[2]]
if (!alvo) {
  console.log('\n  uso: node scripts/paste-supabase-key.js <anon|service>\n')
  process.exit(1)
}

console.log(`\n  Lendo a chave ${alvo.rotulo} da área de transferência\n`)

let chave
try {
  chave = execSync('pbpaste', { encoding: 'utf8' }).trim()
} catch {
  morrer('Não consegui ler a área de transferência (pbpaste).')
}

if (!chave) morrer('Área de transferência vazia.', 'Copie a chave no painel do Supabase primeiro.')

// 1. Integridade — o erro que já nos custou um ciclo inteiro.
const naoAscii = [...chave].filter(c => c.charCodeAt(0) > 127)
if (naoAscii.length) {
  const cps = [...new Set(naoAscii.map(c => 'U+' + c.charCodeAt(0).toString(16).toUpperCase()))]
  morrer(
    `A chave tem ${naoAscii.length} caractere(s) não-ASCII (${cps.join(', ')}).`,
    'Foi copiada de uma saída que mascara segredos. Use o botão de copiar do painel.'
  )
}

if (/\s/.test(chave)) morrer('A chave contém espaço ou quebra de linha.', 'Copie apenas o valor.')

// 2. Formato e papel.
let formato
if (chave.startsWith('eyJ')) {
  if (chave.split('.').length !== 3) morrer('Parece um JWT, mas não tem três partes.', 'Cópia incompleta?')
  const claims = decodificarJwt(chave)
  if (!claims) morrer('JWT ilegível.')
  if (claims.role !== alvo.role) {
    morrer(
      `Esta chave tem role "${claims.role}", e você pediu a "${alvo.role}".`,
      claims.role === 'service_role'
        ? 'Chave secreta jamais vai em NEXT_PUBLIC_* — ela seria servida ao navegador.'
        : 'Copie a outra linha do painel.'
    )
  }
  if (claims.ref && claims.ref !== PROJECT_REF) {
    morrer(`A chave é do projeto "${claims.ref}", não de "${PROJECT_REF}".`)
  }
  formato = `JWT legada, role "${claims.role}"`
} else if (chave.startsWith('sb_publishable_') || chave.startsWith('sb_secret_')) {
  const ehSecreta = chave.startsWith('sb_secret_')
  if (ehSecreta !== (alvo.role === 'service_role')) {
    morrer(
      `Você pediu a ${alvo.rotulo}, mas copiou uma chave ${ehSecreta ? 'secreta' : 'publicável'}.`,
      ehSecreta ? 'Chave secreta nunca vai em NEXT_PUBLIC_*.' : 'Copie a chave secreta.'
    )
  }
  formato = `formato novo (${ehSecreta ? 'sb_secret_' : 'sb_publishable_'})`
} else {
  morrer('Formato irreconhecível.', 'Esperava algo começando com "eyJ", "sb_publishable_" ou "sb_secret_".')
}

console.log(`${OK} Íntegra — ${chave.length} caracteres, só ASCII`)
console.log(`${OK} ${formato}`)
console.log(`${OK} Projeto confere`)

// 3. Grava em .env.local.
if (!fs.existsSync(ENV_FILE)) morrer('.env.local não existe.')

const linhas = fs.readFileSync(ENV_FILE, 'utf8').split('\n')
let achou = false
const novas = linhas.map(l => {
  if (l.startsWith(`${alvo.varName}=`)) {
    achou = true
    return `${alvo.varName}=${chave}`
  }
  return l
})
if (!achou) novas.push(`${alvo.varName}=${chave}`)

fs.writeFileSync(ENV_FILE, novas.join('\n'))

console.log(`${OK} Gravada em .env.local como ${alvo.varName}`)
console.log(`\n  Agora rode: node scripts/verify-supabase.js\n`)
