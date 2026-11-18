import {
  Award, Bike, Compass, Crown, Flame, Footprints, Gem, Medal, Mountain, Rocket, Sprout, Star, Sunrise, Swords, Target, Trophy, Users, Zap,
  type LucideIcon,
} from 'lucide-react'

const registry: Record<string, LucideIcon> = {
  award: Award,
  bike: Bike,
  compass: Compass,
  crown: Crown,
  flame: Flame,
  footprints: Footprints,
  gem: Gem,
  medal: Medal,
  mountain: Mountain,
  rocket: Rocket,
  sprout: Sprout,
  star: Star,
  sunrise: Sunrise,
  swords: Swords,
  target: Target,
  trophy: Trophy,
  users: Users,
  zap: Zap,
}

export function getIcon(name: string): LucideIcon {
  return registry[name] ?? Star
}
