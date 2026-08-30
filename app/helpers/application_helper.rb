module ApplicationHelper
  def icon_tag(name, css_class: "w-5 h-5")
    case name.to_s
    when "chef-hat"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 13.87A4 4 0 0 1 7.41 6a5.11 5.11 0 0 1 1.05-1.54 5 5 0 0 1 7.08 0A5.11 5.11 0 0 1 16.59 6 4 4 0 0 1 18 13.87V21H6v-7.13zM6 17h12"/></svg>))
    when "calendar"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>))
    when "shopping-cart"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z"/></svg>))
    when "book-open"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/></svg>))
    when "printer"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 17h2a2 2 0 002-2v-4a2 2 0 00-2-2H5a2 2 0 00-2 2v4a2 2 0 002 2h2m2 4h6a2 2 0 002-2v-4H7v4a2 2 0 002 2zm8-12V5a2 2 0 00-2-2H9a2 2 0 00-2 2v4h10z"/></svg>))
    when "heart"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"/></svg>))
    when "heart-solid"
      raw(%(<svg class="#{css_class}" fill="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z" clip-rule="evenodd"/></svg>))
    when "plus"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>))
    when "pencil", "edit"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg>))
    when "check"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>))
    when "sparkles"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z"/></svg>))
    when "users"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/></svg>))
    when "trash"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>))
    when "chevron-down"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/></svg>))
    when "arrow-right"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"/></svg>))
    when "archive"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>))
    when "link"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/></svg>))
    when "utensils"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2M7 2v20M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3zm0 0v7"/></svg>))
    when "star"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"/></svg>))
    when "smile"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="10" stroke-width="2"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01"/></svg>))
    when "flame"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 18.657A8 8 0 016.343 7.343S7 9 9 10c0-2 .5-5 2.986-7C14 5 16.09 5.777 17.656 7.343A7.975 7.975 0 0120 13a7.975 7.975 0 01-2.343 5.657z"/></svg>))
    when "award"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="8" r="7" stroke-width="2"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.21 13.89L7 23l5-3 5 3-1.21-9.12"/></svg>))
    when "user"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>))
    when "cog"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>))
    when "shield", "shield-check"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/></svg>))
    when "shield-outline", "shield-off"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.618 5.984A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/></svg>))
    when "key"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"/></svg>))
    when "lock"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg>))
    when "mail"
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/></svg>))
    else
      raw(%(<svg class="#{css_class}" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="10" stroke-width="2"/></svg>))
    end
  end

  def pantry_icon_tag(item_or_name, category = nil, css_class: "w-6 h-6")
    name = item_or_name.is_a?(PantryItem) ? item_or_name.name : item_or_name.to_s
    cat = item_or_name.is_a?(PantryItem) ? item_or_name.aisle_category : category
    explicit_emoji = item_or_name.is_a?(PantryItem) ? item_or_name.emoji : nil

    if explicit_emoji.present?
      case explicit_emoji
      when "pepper-shaker"
        return raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Black Pepper"><path d="M10 5C10 3.89543 10.8954 3 12 3H20C21.1046 3 22 3.89543 22 5V8H10V5Z" fill="#94A3B8"/><circle cx="13" cy="5.5" r="0.75" fill="#334155"/><circle cx="16" cy="5.5" r="0.75" fill="#334155"/><circle cx="19" cy="5.5" r="0.75" fill="#334155"/><path d="M8 9H24L22.5 27C22.3 28.1 21.3 29 20.2 29H11.8C10.7 29 9.7 28.1 9.5 27L8 9Z" fill="#CBD5E1" fill-opacity="0.3" stroke="#94A3B8" stroke-width="1.5"/><path d="M9.5 13H22.5L21.8 26C21.7 26.6 21.2 27 20.6 27H11.4C10.8 27 10.3 26.6 10.2 26L9.5 13Z" fill="#1E293B"/><circle cx="13" cy="17" r="1" fill="#475569"/><circle cx="17" cy="16" r="1.2" fill="#0F172A"/><circle cx="19" cy="20" r="1" fill="#475569"/><circle cx="14" cy="22" r="1.1" fill="#334155"/><circle cx="17" cy="24" r="0.9" fill="#0F172A"/><circle cx="12" cy="25" r="0.8" fill="#475569"/><path d="M11 11L12 25" stroke="white" stroke-width="1.2" stroke-linecap="round" stroke-opacity="0.6"/></svg>))
      when "sugar-bag"
        return raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Sugar"><path d="M6 10C6 8.89543 6.89543 8 8 8H24C25.1046 8 26 8.89543 26 10L24.5 27C24.3 28.1 23.3 29 22.2 29H9.8C8.7 29 7.7 28.1 7.5 27L6 10Z" fill="#FEF3C7" stroke="#D97706" stroke-width="1.5"/><path d="M5 6C5 5.44772 5.44772 5 6 5H26C26.5523 5 27 5.44772 27 6V8C27 8.55228 26.5523 9 26 9H6C5.44772 9 5 8.55228 5 8V6Z" fill="#FDE68A" stroke="#D97706" stroke-width="1.5"/><rect x="9.5" y="14" width="13" height="9" rx="2" fill="#FFFFFF" stroke="#F59E0B" stroke-width="1"/><text x="16" y="20.5" font-family="system-ui, -apple-system, sans-serif" font-size="6.5" font-weight="900" fill="#D97706" text-anchor="middle">SUGAR</text><circle cx="21" cy="11.5" r="0.75" fill="#F59E0B"/><circle cx="11" cy="11.5" r="0.75" fill="#F59E0B"/></svg>))
      when "oil-bottle"
        return raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Cooking Oil"><path d="M14 2H18V6H14V2Z" fill="#F59E0B"/><path d="M13 6H19V9H13V6Z" fill="#D97706"/><path d="M11 11C11 9.89543 11.8954 9 13 9H19C20.1046 9 21 9.89543 21 11L22.5 27.5C22.6 28.3 22 29 21.2 29H10.8C10 29 9.4 28.3 9.5 27.5L11 11Z" fill="#FEF08A" stroke="#CA8A04" stroke-width="1.5"/><path d="M11.5 14H20.5L21.7 27.5C21.8 27.8 21.5 28 21.2 28H10.8C10.5 28 10.2 27.8 10.3 27.5L11.5 14Z" fill="#EAB308"/><path d="M16 18C15 19.5 14 20.5 14 21.5C14 22.6 14.9 23.5 16 23.5C17.1 23.5 18 22.6 18 21.5C18 20.5 17 19.5 16 18Z" fill="#CA8A04"/><path d="M13 13L12.5 25" stroke="white" stroke-width="1" stroke-linecap="round" stroke-opacity="0.8"/></svg>))
      when "spice-jar"
        return raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Spice Jar"><path d="M10 4C10 3.44772 10.4477 3 11 3H21C21.5523 3 22 3.44772 22 4V8H10V4Z" fill="#B45309"/><rect x="8" y="9" width="16" height="19" rx="3" fill="#F8FAFC" fill-opacity="0.4" stroke="#94A3B8" stroke-width="1.5"/><rect x="9.5" y="13" width="13" height="13.5" rx="1.5" fill="#FDE68A"/><rect x="8" y="16" width="16" height="7" fill="#FFFFFF" stroke="#CBD5E1" stroke-width="0.75"/><rect x="10.5" y="18.5" width="11" height="2" rx="1" fill="#64748B"/></svg>))
      else
        return raw(%(<span class="text-xl select-none leading-none inline-flex items-center justify-center">#{explicit_emoji}</span>))
      end
    end

    n = name.to_s.downcase.strip
    case n
    when "pepper-shaker", /black pepper|pepper powder|peppercorn|cracked pepper/
      raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Black Pepper"><path d="M10 5C10 3.89543 10.8954 3 12 3H20C21.1046 3 22 3.89543 22 5V8H10V5Z" fill="#94A3B8"/><circle cx="13" cy="5.5" r="0.75" fill="#334155"/><circle cx="16" cy="5.5" r="0.75" fill="#334155"/><circle cx="19" cy="5.5" r="0.75" fill="#334155"/><path d="M8 9H24L22.5 27C22.3 28.1 21.3 29 20.2 29H11.8C10.7 29 9.7 28.1 9.5 27L8 9Z" fill="#CBD5E1" fill-opacity="0.3" stroke="#94A3B8" stroke-width="1.5"/><path d="M9.5 13H22.5L21.8 26C21.7 26.6 21.2 27 20.6 27H11.4C10.8 27 10.3 26.6 10.2 26L9.5 13Z" fill="#1E293B"/><circle cx="13" cy="17" r="1" fill="#475569"/><circle cx="17" cy="16" r="1.2" fill="#0F172A"/><circle cx="19" cy="20" r="1" fill="#475569"/><circle cx="14" cy="22" r="1.1" fill="#334155"/><circle cx="17" cy="24" r="0.9" fill="#0F172A"/><circle cx="12" cy="25" r="0.8" fill="#475569"/><path d="M11 11L12 25" stroke="white" stroke-width="1.2" stroke-linecap="round" stroke-opacity="0.6"/></svg>))
    when "sugar-bag", /granulated sugar|cane sugar|brown sugar|white sugar|sugar bag/
      raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Sugar"><path d="M6 10C6 8.89543 6.89543 8 8 8H24C25.1046 8 26 8.89543 26 10L24.5 27C24.3 28.1 23.3 29 22.2 29H9.8C8.7 29 7.7 28.1 7.5 27L6 10Z" fill="#FEF3C7" stroke="#D97706" stroke-width="1.5"/><path d="M5 6C5 5.44772 5.44772 5 6 5H26C26.5523 5 27 5.44772 27 6V8C27 8.55228 26.5523 9 26 9H6C5.44772 9 5 8.55228 5 8V6Z" fill="#FDE68A" stroke="#D97706" stroke-width="1.5"/><rect x="9.5" y="14" width="13" height="9" rx="2" fill="#FFFFFF" stroke="#F59E0B" stroke-width="1"/><text x="16" y="20.5" font-family="system-ui, -apple-system, sans-serif" font-size="6.5" font-weight="900" fill="#D97706" text-anchor="middle">SUGAR</text><circle cx="21" cy="11.5" r="0.75" fill="#F59E0B"/><circle cx="11" cy="11.5" r="0.75" fill="#F59E0B"/></svg>))
    when "oil-bottle", /vegetable oil|canola oil|sunflower oil|corn oil|cooking oil/
      raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Cooking Oil"><path d="M14 2H18V6H14V2Z" fill="#F59E0B"/><path d="M13 6H19V9H13V6Z" fill="#D97706"/><path d="M11 11C11 9.89543 11.8954 9 13 9H19C20.1046 9 21 9.89543 21 11L22.5 27.5C22.6 28.3 22 29 21.2 29H10.8C10 29 9.4 28.3 9.5 27.5L11 11Z" fill="#FEF08A" stroke="#CA8A04" stroke-width="1.5"/><path d="M11.5 14H20.5L21.7 27.5C21.8 27.8 21.5 28 21.2 28H10.8C10.5 28 10.2 27.8 10.3 27.5L11.5 14Z" fill="#EAB308"/><path d="M16 18C15 19.5 14 20.5 14 21.5C14 22.6 14.9 23.5 16 23.5C17.1 23.5 18 22.6 18 21.5C18 20.5 17 19.5 16 18Z" fill="#CA8A04"/><path d="M13 13L12.5 25" stroke="white" stroke-width="1" stroke-linecap="round" stroke-opacity="0.8"/></svg>))
    when "spice-jar", /garlic powder|onion powder|garlic salt|onion flakes/
      raw(%(<svg class="#{css_class} inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Spice Jar"><path d="M10 4C10 3.44772 10.4477 3 11 3H21C21.5523 3 22 3.44772 22 4V8H10V4Z" fill="#B45309"/><rect x="8" y="9" width="16" height="19" rx="3" fill="#F8FAFC" fill-opacity="0.4" stroke="#94A3B8" stroke-width="1.5"/><rect x="9.5" y="13" width="13" height="13.5" rx="1.5" fill="#FDE68A"/><rect x="8" y="16" width="16" height="7" fill="#FFFFFF" stroke="#CBD5E1" stroke-width="0.75"/><rect x="10.5" y="18.5" width="11" height="2" rx="1" fill="#64748B"/></svg>))
    else
      emoji = PantryItem.emoji_for(name, cat)
      raw(%(<span class="text-xl select-none leading-none inline-flex items-center justify-center">#{emoji}</span>))
    end
  end
end
