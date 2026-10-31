//
//  LockRow.swift
//
//
//  Created by Alsey Coleman Miller on 10/30/26.
//

import SwiftUI
import ELinkSmart

struct LockRow: View {

    let lock: ELinkSmartLock

    var body: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text("Padlock")
                    .font(.title3)
                Text(verbatim: lock.name)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
        }
    }
}
