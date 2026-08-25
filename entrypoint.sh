#!/bin/sh
set -e

# ============================================================
#  Injeção de variáveis de ambiente em runtime
# ============================================================
#
# As variáveis NEXT_PUBLIC_* são embutidas pelo Next.js no momento do build.
# Como a imagem é construída sem os valores reais, o build usa placeholders e
# este script os substitui pelos valores de runtime antes de subir o servidor.
#
# A validação abaixo existe porque uma variável ausente vira string vazia no
# sed, e a aplicação subiria quebrada sem um único erro no log.

fail() {
  echo "❌ $1" >&2
  exit 1
}

# --- Obrigatórias --------------------------------------------------------
[ -n "$NEXT_PUBLIC_SUPABASE_URL" ]      || fail "NEXT_PUBLIC_SUPABASE_URL não definida."
[ -n "$NEXT_PUBLIC_SUPABASE_ANON_KEY" ] || fail "NEXT_PUBLIC_SUPABASE_ANON_KEY não definida."
[ -n "$SUPABASE_SERVICE_ROLE_KEY" ]     || fail "SUPABASE_SERVICE_ROLE_KEY não definida."
[ -n "$NEXT_PUBLIC_APP_URL" ]           || fail "NEXT_PUBLIC_APP_URL não definida."

# --- A chave pública não pode ser uma chave secreta ----------------------
# Tudo que é NEXT_PUBLIC_* vai para o JavaScript entregue ao navegador.
# Já aconteceu de a chave secreta do Supabase ser publicada por engano aqui.
case "$NEXT_PUBLIC_SUPABASE_ANON_KEY" in
  sb_secret_*|service_role*)
    fail "NEXT_PUBLIC_SUPABASE_ANON_KEY contém uma chave SECRETA.
   Tudo com prefixo NEXT_PUBLIC_ é servido ao navegador de todo visitante.
   Use a chave anon/publishable aqui e a secreta em SUPABASE_SERVICE_ROLE_KEY."
    ;;
esac

# --- A chave precisa ser ASCII imprimível --------------------------------
# Chaves copiadas de terminais, chats ou logs que mascaram segredos vêm com o
# valor substituído por bullets (U+2022) ou reticências. O app sobe, mas todo
# fetch falha com "String contains non ISO-8859-1 code point", porque cabeçalho
# HTTP não aceita caractere fora de Latin-1. Falhar aqui é muito mais barato.
if printf '%s' "$NEXT_PUBLIC_SUPABASE_ANON_KEY" | LC_ALL=C grep -q '[^ -~]'; then
  fail "NEXT_PUBLIC_SUPABASE_ANON_KEY contém caractere não-ASCII.
   Provavelmente foi copiada de uma saída que mascara segredos (os '•').
   Copie direto do painel do Supabase, em Settings > API Keys."
fi

# A chave anon em formato JWT carrega \"role\":\"anon\" no payload. Se vier um JWT
# com service_role, é a chave errada — mesmo problema, outro formato.
case "$NEXT_PUBLIC_SUPABASE_ANON_KEY" in
  eyJ*)
    payload=$(echo "$NEXT_PUBLIC_SUPABASE_ANON_KEY" | cut -d. -f2)
    # base64url -> base64, com padding
    decoded=$(echo "${payload}==" | tr '_-' '/+' | base64 -d 2>/dev/null || true)
    case "$decoded" in
      *service_role*)
        fail "NEXT_PUBLIC_SUPABASE_ANON_KEY é um JWT com role service_role.
   Use a chave anon."
        ;;
    esac
    ;;
esac

# --- Opcionais: podem ficar vazias -------------------------------------
# Stripe e reCAPTCHA são desligados graciosamente quando não configurados.

echo "🔧 Injetando variáveis de ambiente no bundle..."

find /app/.next -type f -name "*.js" -exec sed -i \
  -e "s|https://buildplaceholder.supabase.co|${NEXT_PUBLIC_SUPABASE_URL}|g" \
  -e "s|eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.buildplaceholder|${NEXT_PUBLIC_SUPABASE_ANON_KEY}|g" \
  -e "s|https://buildplaceholder.app|${NEXT_PUBLIC_APP_URL}|g" \
  -e "s|pk_test_buildplaceholder|${NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY}|g" \
  -e "s|buildplaceholder_recaptcha|${NEXT_PUBLIC_RECAPTCHA_SITE_KEY}|g" \
  {} +

echo "✅ Variáveis injetadas. Iniciando servidor..."

exec node server.js
