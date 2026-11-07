import { useCallback, useEffect, useState } from 'react'
import { mensagemErro } from './supabase'

// Hook mínimo de leitura: executa a consulta, guarda dados/erro e expõe recarregar().
export function useDados<T>(consulta: () => PromiseLike<{ data: T | null; error: unknown }>, deps: unknown[]) {
  const [dados, setDados] = useState<T | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [carregando, setCarregando] = useState(true)

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const executar = useCallback(consulta, deps)

  const recarregar = useCallback(async () => {
    setCarregando(true)
    try {
      const { data, error } = await executar()
      if (error) throw error
      setDados(data)
      setErro(null)
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setCarregando(false)
    }
  }, [executar])

  useEffect(() => {
    recarregar()
  }, [recarregar])

  return { dados, erro, carregando, recarregar }
}
