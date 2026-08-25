-- =============================================
-- Corrige o trigger de criação de assinatura de teste
-- =============================================
--
-- Problema:
--   Cadastrar usuário falhava com "Database error saving new user".
--
--   create_trial_subscription() roda num AFTER INSERT ON auth.users. Como não
--   era SECURITY DEFINER, executava com o papel que faz o INSERT em auth.users
--   — o supabase_auth_admin — que não tem privilégio nas tabelas de public nem
--   escapa do RLS. O INSERT em user_subscriptions era recusado, o trigger
--   abortava e derrubava a transação inteira do cadastro.
--
-- Solução:
--   Recriar a função como SECURITY DEFINER, com search_path fixo. Ela passa a
--   executar como dona das tabelas, que tem os privilégios necessários e não
--   está sujeita a RLS.
--
--   Mesmo padrão de 013: quando uma função precisa de privilégio que o chamador
--   não tem, isso se declara — não se contorna com service role na aplicação.

CREATE OR REPLACE FUNCTION create_trial_subscription()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    trial_plan_id UUID;
    nova_assinatura_id UUID;
BEGIN
    SELECT id INTO trial_plan_id
    FROM subscription_plans
    WHERE is_trial = true AND is_active = true
    LIMIT 1;

    IF trial_plan_id IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO user_subscriptions (
        user_id, plan_id, status, start_date, end_date, is_trial, trial_used
    )
    VALUES (
        NEW.id, trial_plan_id, 'active', NOW(), NOW() + INTERVAL '3 days', true, true
    )
    RETURNING id INTO nova_assinatura_id;

    -- Antes o id era recuperado com um SELECT ... ORDER BY created_at LIMIT 1,
    -- que podia pegar a linha errada em cadastros simultâneos. RETURNING dá o
    -- id exato da linha recém-inserida.
    INSERT INTO subscription_history (
        user_id, subscription_id, action, new_plan_id, details
    )
    VALUES (
        NEW.id,
        nova_assinatura_id,
        'created',
        trial_plan_id,
        '{"type": "trial", "auto_created": true}'::jsonb
    );

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION create_trial_subscription() IS
  'Cria a assinatura de teste no cadastro. SECURITY DEFINER porque o trigger roda como supabase_auth_admin, sem privilégio em public.';
